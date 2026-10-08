#!/usr/bin/env bash
# Public-readiness scan for this template (no external tools needed). Exit 1 on any finding.
# Checks: forbidden files, emails, IPv4 (except 127.0.0.1 / 0.0.0.0 / Docker DNS 127.0.0.11), absolute home paths,
# private keys, common token formats, and long hex/base64 strings not pinned in UPSTREAM.lock.
# CI additionally runs gitleaks (see .github/workflows/validate.yml).
# sed indents every line in multiline diagnostics.
# shellcheck disable=SC2001
set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
cd "${ROOT_DIR}"
found=0
report() { echo "FINDING: $1"; found=1; }

# Text files tracked-or-not, excluding git metadata and local-only dirs.
files=()
while IFS= read -r -d '' f; do files+=("$f"); done < <(
  find . -type f ! -path './.git/*' ! -path './upstream/*' ! -path './backups/*' -print0)

# 1) forbidden files (secrets / data must never be committed)
for f in "${files[@]}"; do
  case "$f" in
    ./.env|./config/providers.env|*.pem|*.key|*/id_rsa*|*/id_ed25519*|*.sql|*.sql.gz) report "forbidden file: $f";;
  esac
done
[ -d backups ] && [ -n "$(ls -A backups 2>/dev/null)" ] && echo "note: ./backups exists locally (gitignored)"

scan() { # $1 = description, $2 = ERE
  local hits
  hits="$(grep -nIE "$2" "${files[@]}" 2>/dev/null || true)"
  [ -n "${hits}" ] && { report "$1"; echo "${hits}" | sed 's/^/    /'; }
  return 0
}
scan "email address" '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z0-9.-]*[A-Za-z]{2,}'
# Pattern literals are split ('/Us''ers') so this script does not match itself.
home_re='(/Us''ers/[A-Za-z0-9]|/ho''me/[a-z][a-z0-9_-]+)'
home_ok='/ho''me/deploy([/ ]|$)'
home_hits="$(grep -nIE "${home_re}" "${files[@]}" 2>/dev/null | grep -vE "${home_ok}" || true)"
[ -n "${home_hits}" ] && { report "absolute home path (only the /home/deploy example is allowed)"; echo "${home_hits}" | sed 's/^/    /'; }
scan "private key" '-----BEGIN [A-Z ]*PRIVATE KEY-----'
scan "token format" '(sk_(live|test)_[A-Za-z0-9]{10,}|rk_(live|test)_[A-Za-z0-9]{10,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]{10,})'

# IPv4 other than loopback / any-address
ip_hits="$(grep -noIE '([0-9]{1,3}\.){3}[0-9]{1,3}' "${files[@]}" 2>/dev/null | grep -vE ':(127\.0\.0\.1|127\.0\.0\.11|0\.0\.0\.0)$' || true)"
[ -n "${ip_hits}" ] && { report "IPv4 address"; echo "${ip_hits}" | sed 's/^/    /'; }

# Long hex / base64 strings, allowed only if pinned in UPSTREAM.lock (commit SHAs, digests, checksums)
allow="$(grep -oE '[0-9a-f]{32,}' UPSTREAM.lock | sort -u)"
is_allowed() { # value contains a pinned hex string -> allowed
  local v="$1" a
  while IFS= read -r a; do [ -n "$a" ] && [[ "$v" == *"$a"* ]] && return 0; done <<< "${allow}"
  return 1
}
while IFS= read -r hit; do
  [ -z "${hit}" ] && continue
  val="${hit#*:*:}"
  is_allowed "${val}" && continue
  if [[ "${val}" =~ ^[0-9a-f]{32,}$ ]]; then report "unpinned hex string: ${hit}"; continue; fi
  # base64-like: only flag when it mixes digits, upper and lower case (paths/words do not)
  [[ "${val}" =~ [0-9] && "${val}" =~ [A-Z] && "${val}" =~ [a-z] ]] && report "high-entropy string: ${hit}"
done < <(grep -noIE '[0-9a-f]{32,}|[A-Za-z0-9+/]{40,}={0,2}' "${files[@]}" 2>/dev/null | grep -v '^./UPSTREAM.lock:' || true)

if [ "${found}" -ne 0 ]; then echo "secret scan: FAILED"; exit 1; fi
echo "secret scan: clean (${#files[@]} files)"
