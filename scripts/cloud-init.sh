#!/usr/bin/env bash
# Render reviewable cloud-init; stdout contains no secrets or cloud account tokens.
set -Eeuo pipefail
provider="${1:-}"; revision="${2:-}"
case "$provider" in vultr|hetzner-cloud) ;; *) echo 'Usage: scripts/cloud-init.sh {vultr|hetzner-cloud} FULL_COMMIT_SHA > cloud-init.yml' >&2; exit 2;; esac
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo 'Pass a full, published template commit SHA (40 lowercase hex characters).' >&2; exit 2; }
cat <<EOF
#cloud-config
# Select Ubuntu 24.04 x86_64, >=8GB RAM, >=40GB free disk and an SSH key in your cloud console.
# Allow SSH inbound only. First build can take an hour; monitor /var/log/artcraft-deploy.log.
package_update: true
packages: [git, curl, ca-certificates, openssl]
swap:
  filename: /swap-artcraft
  size: 8589934592
  maxsize: 8589934592
runcmd:
  - [git, clone, 'https://github.com/junwonkim07/artcraft-personal-server.git', /opt/artcraft-personal-server]
  - [git, -C, /opt/artcraft-personal-server, checkout, --detach, '$revision']
  - [bash, -c, 'cd /opt/artcraft-personal-server && test "\$(git rev-parse HEAD)" = "$revision" && ./scripts/deploy.sh --provider $provider --apply --install-docker > /var/log/artcraft-deploy.log 2>&1']
EOF
