#!/usr/bin/env bash
# shellcheck disable=SC2016 # single quotes intentional: vars expand inside containers
# Restore a backup made by scripts/backup.sh. Usage: scripts/restore.sh backups/<timestamp>
#
# Order: verify files + checksums (nothing is stopped yet) -> explicit confirmation ->
# record running services -> stop writers (storyteller-web) -> restore MySQL (drops and recreates
# the storyteller database) -> restore MinIO buckets (mirror --overwrite --remove) -> put services
# back exactly as they were.
# Non-interactive use: RESTORE_CONFIRM=restore scripts/restore.sh backups/<ts>
# On failure: exits non-zero and, by default, LEAVES WRITERS (storyteller-web) STOPPED so the API
# never runs against a half-restored database. Temporarily started data services are still stopped.
# Set RESTORE_RESTART_ON_FAILURE=1 to restore the exact prior running state even on failure.
set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

src_arg="${1:?usage: scripts/restore.sh backups/<timestamp>}"
[ -d "${src_arg}" ] || { echo "not a directory: ${src_arg}" >&2; exit 1; }
src="$(cd "${src_arg}" && pwd)"
case "$(basename "${src}")" in .*.partial) echo "refusing to restore a partial backup" >&2; exit 1;; esac
for f in mysql-storyteller.sql.gz SHA256SUMS MANIFEST; do
  [ -f "${src}/${f}" ] || { echo "missing ${src}/${f}" >&2; exit 1; }
done
for b in "${BUCKETS[@]}"; do [ -d "${src}/minio/${b}" ] || { echo "missing ${src}/minio/${b}" >&2; exit 1; }; done
echo "verifying checksums..."
( cd "${src}" && sha256_check SHA256SUMS ) || { echo "checksum verification FAILED; nothing was changed" >&2; exit 1; }
gzip -t "${src}/mysql-storyteller.sql.gz" || { echo "mysql dump is not valid gzip; nothing was changed" >&2; exit 1; }
backup_sha="$(grep -E '^upstream_sha=' "${src}/MANIFEST" | cut -d= -f2)"
if [ "${backup_sha}" != "$(lock_value UPSTREAM_SHA)" ]; then
  echo "WARNING: backup was taken at upstream ${backup_sha}, current pin is $(lock_value UPSTREAM_SHA)." >&2
fi

if [ "${RESTORE_CONFIRM:-}" != "restore" ]; then
  if [ -t 0 ]; then
    read -r -p "This will OVERWRITE the storyteller database and buckets ${BUCKETS[*]}. Type 'restore' to continue: " ans
    [ "${ans}" = "restore" ] || { echo "aborted; nothing was changed"; exit 1; }
  else
    echo "not a terminal: set RESTORE_CONFIRM=restore to confirm. Nothing was changed." >&2; exit 1
  fi
fi

completed=0
cleanup() {
  local rc=$?
  trap - EXIT INT TERM ERR
  set +e
  if [ "${completed}" -ne 1 ]; then
    [ "${rc}" -eq 0 ] && rc=1
    echo "RESTORE FAILED. Database and/or buckets may be PARTIALLY restored. Re-run the restore before using the server." >&2
    if [ "${RESTORE_RESTART_ON_FAILURE:-0}" = "1" ]; then
      echo "RESTORE_RESTART_ON_FAILURE=1: restarting writers despite the failure." >&2
    else
      echo "Leaving writers stopped: ${STOPPED_BY_US[*]:-(none)}. Fix the problem and re-run restore," >&2
      echo "or start them manually with: docker compose start storyteller-web" >&2
      STOPPED_BY_US=()
    fi
  fi
  restore_running_state || { echo "WARNING: could not fully restore the original service state" >&2; [ "${rc}" -eq 0 ] && rc=1; }
  exit "${rc}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'echo "error on line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

capture_running_state
quiesce_writers

echo "restoring mysql (drops and recreates database storyteller)..."
gunzip -c "${src}/mysql-storyteller.sql.gz" \
  | compose exec -T mysql sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'

echo "restoring minio buckets: ${BUCKETS[*]}"
compose run --rm --no-deps -v "${src}/minio:/backup:ro" minio-init \
  'set -e; mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null; for b in '"${BUCKETS[*]}"'; do mc mb --ignore-existing "local/$b" >/dev/null; mc mirror --quiet --overwrite --remove "/backup/$b" "local/$b"; done'

completed=1
echo "restore complete from ${src}"
