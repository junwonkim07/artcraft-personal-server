#!/usr/bin/env bash
# Shared helpers. Source from other scripts (bash 3.2 compatible: macOS default bash).
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT_DIR

# Services that write to MySQL / MinIO. Stopped during backup/restore for a consistent snapshot.
WRITER_SERVICES=(storyteller-web)
# Services that must be running to dump/restore data.
DATA_SERVICES=(mysql minio)
# Buckets created by minio-init in docker-compose.yml.
BUCKETS=(artcraft-private artcraft-public artcraft-public-gc)

lock_value() { grep -E "^$1=" "${ROOT_DIR}/UPSTREAM.lock" | head -n1 | cut -d= -f2 | awk '{print $1}'; }
compose() { docker compose --project-directory "${ROOT_DIR}" -f "${ROOT_DIR}/docker-compose.yml" "$@"; }

# Read KEY from .env without sourcing it (empty if missing/commented).
env_value() { grep -E "^$1=" "${ROOT_DIR}/.env" 2>/dev/null | tail -n1 | cut -d= -f2- || true; }

sha256_create() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
sha256_check() { if command -v sha256sum >/dev/null; then sha256sum -c --quiet "$1"; else shasum -a 256 -c --quiet "$1"; fi; }

contains() { local needle="$1" item; shift; for item in "$@"; do [ "${item}" = "${needle}" ] && return 0; done; return 1; }

# ---- running-state bookkeeping (used by backup.sh / restore.sh) ----
ORIG_RUNNING=()   # services running when the script started
STOPPED_BY_US=()  # writers we stopped (restart them afterwards)
STARTED_BY_US=()  # data services we started temporarily (stop them afterwards)

capture_running_state() {
  local svc out
  out="$(compose ps --status running --services)" || { echo "cannot query compose state" >&2; return 1; }
  ORIG_RUNNING=()
  while IFS= read -r svc; do [ -n "${svc}" ] && ORIG_RUNNING+=("${svc}"); done <<< "${out}"
  echo "running before: ${ORIG_RUNNING[*]:-(none)}"
}

# Start missing data services, stop running writers. Records every action BEFORE doing it,
# so the cleanup trap can undo partial work.
quiesce_writers() {
  local svc
  for svc in "${DATA_SERVICES[@]}"; do
    if ! contains "${svc}" ${ORIG_RUNNING[@]+"${ORIG_RUNNING[@]}"}; then
      STARTED_BY_US+=("${svc}")
      echo "starting ${svc} temporarily"
      compose up -d --no-deps --wait "${svc}"
    fi
  done
  for svc in "${WRITER_SERVICES[@]}"; do
    if contains "${svc}" ${ORIG_RUNNING[@]+"${ORIG_RUNNING[@]}"}; then
      STOPPED_BY_US+=("${svc}")
      echo "stopping writer ${svc}"
      compose stop "${svc}"
    fi
  done
}

# Put services back exactly as they were: restart only writers we stopped,
# stop only data services we started. Never starts anything that was stopped before.
restore_running_state() {
  local svc rc=0
  for svc in ${STOPPED_BY_US[@]+"${STOPPED_BY_US[@]}"}; do
    echo "restarting ${svc}"
    compose start "${svc}" || { echo "WARNING: failed to restart ${svc}" >&2; rc=1; }
  done
  for svc in ${STARTED_BY_US[@]+"${STARTED_BY_US[@]}"}; do
    echo "stopping temporarily started ${svc}"
    compose stop "${svc}" || { echo "WARNING: failed to stop ${svc}" >&2; rc=1; }
  done
  STOPPED_BY_US=(); STARTED_BY_US=()
  return "${rc}"
}
