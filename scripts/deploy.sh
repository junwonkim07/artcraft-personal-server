#!/usr/bin/env bash
# Provider selector for the same private, single-host Compose stack.
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
provider=""; apply=false; install_docker=false
usage() {
  cat <<'EOF'
Usage: scripts/deploy.sh [--provider NAME] [--plan | --apply] [--install-docker]
Providers: vultr, hetzner-cloud, hetzner-auction, ubuntu
The default prints a plan. --apply installs on THIS machine; it never rents or reimages a server.
Run on an existing Ubuntu 24.04 x86_64 server. --install-docker permits installing Docker via official apt.
Vercel and Neon cannot run the complete stack; selecting either explains the limitation and exits 2.
EOF
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --provider) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; provider="$2"; shift 2 ;;
    --apply) apply=true; shift ;;
    --plan) apply=false; shift ;;
    --install-docker) install_docker=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
if [ -z "$provider" ]; then
  if [ ! -t 0 ]; then usage >&2; exit 2; fi
  echo 'Choose your deployment target:'
  select provider in vultr hetzner-cloud hetzner-auction ubuntu vercel neon; do
    [ -n "$provider" ] && break
  done
fi
case "$provider" in
  vultr|hetzner-cloud|hetzner-auction|ubuntu) ;;
  vercel) echo 'Vercel can host the frontend separately, but cannot run this Compose stack. A public HTTPS backend, origin/cookie configuration and media routing are still needed. No one-click Vercel deployment is provided. See docs/deployment.md.'; exit 2 ;;
  neon) echo 'Neon provides PostgreSQL. ArtCraft uses MySQL queries and migrations; replacing MYSQL_URL with a Neon URL will not work. A database port is required. See docs/deployment.md.'; exit 2 ;;
  *) echo "Unknown provider: $provider" >&2; exit 2 ;;
esac
cat <<EOF
Target: $provider (Ubuntu 24.04 x86_64, existing machine)
Directory: $ROOT_DIR
Steps: verify host -> prepare Docker -> generate missing secrets -> build -> start -> check health/storage
Access: SSH tunnel to localhost:4201; only SSH needs to be allowed by your provider firewall.
No server purchase, disk formatting, SSH configuration change, or public web-port opening.
EOF
[ "$provider" != hetzner-auction ] || echo 'Install Ubuntu on the dedicated server first. This script does not run Rescue/installimage or change RAID.'
$apply || { echo 'Plan only. On your chosen server, rerun with sudo and --apply.'; exit 0; }
[ "$EUID" -eq 0 ] || { echo 'Run --apply with sudo on the chosen server.' >&2; exit 1; }
# shellcheck disable=SC1091
source /etc/os-release
if [ "${ID:-}" != ubuntu ] || [ "${VERSION_ID:-}" != 24.04 ] || [ "$(uname -m)" != x86_64 ]; then
  echo 'Supported installer host: Ubuntu 24.04 x86_64 (not Rescue, macOS or ARM).' >&2; exit 1
fi
if ! command -v openssl >/dev/null || ! command -v curl >/dev/null; then
  echo 'Install openssl and curl first.' >&2; exit 1
fi
# Never repair partial secret sets by generating a different database password.
if { [ -e "$ROOT_DIR/.env" ] && [ ! -e "$ROOT_DIR/config/providers.env" ]; } ||
   { [ ! -e "$ROOT_DIR/.env" ] && [ -e "$ROOT_DIR/config/providers.env" ]; }; then
  echo 'Partial secret configuration found. Restore the matching .env and config/providers.env before continuing.' >&2; exit 1
fi
if ! command -v docker >/dev/null; then
  $install_docker || { echo 'Docker missing. Install it or pass --install-docker.' >&2; exit 1; }
  # Do not remove or replace a pre-existing distribution installation automatically.
  for pkg in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed'; then
      echo "Conflicting package $pkg is installed. Follow the Docker migration guide first." >&2; exit 1
    fi
  done
  apt-get update
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable' > /etc/apt/sources.list.d/artcraft-docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
docker compose version >/dev/null
systemctl enable --now docker
# Raise only when necessary; never lower a host's existing ES requirement.
if [ "$(sysctl -n vm.max_map_count)" -lt 262144 ]; then
  echo 'vm.max_map_count=262144' > /etc/sysctl.d/99-artcraft.conf
  sysctl -p /etc/sysctl.d/99-artcraft.conf
fi
if [ ! -e "$ROOT_DIR/.env" ]; then "$ROOT_DIR/scripts/generate-secrets.sh"; fi
cd "$ROOT_DIR"
docker compose config --quiet
docker compose build
docker compose up -d --wait --wait-timeout 300
./scripts/status.sh
./scripts/verify-storage-policy.sh
echo "Ready. On your computer: ssh -N -L 4201:127.0.0.1:4201 YOUR_SSH_USER@YOUR_SERVER"
echo 'Then open http://localhost:4201. Credentials and data remain on this server.'
