#!/usr/bin/env bash
# shellcheck disable=SC2016 # single quotes intentional: vars expand inside containers
# Consistent backup: stops writers (storyteller-web), dumps MySQL and mirrors MinIO buckets,
# then puts every service back into the exact state it was in before.
#
# Output: ./backups/<UTC timestamp>/ (written to ./backups/.<ts>.partial first, renamed only on success).
# Retention: OFF by default. Set BACKUP_RETENTION_DAYS=<N> (env or .env) to delete completed backups older than N days.
# On failure: exit non-zero, the partial directory is removed (KEEP_PARTIAL=1 keeps it for debugging).
set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
umask 077

ts="$(date -u +%Y%m%dT%H%M%SZ)"
backups_dir="${ROOT_DIR}/backups"
final="${backups_dir}/${ts}"
partial="${backups_dir}/.${ts}.partial"
completed=0

cleanup() {
  local rc=$?
  trap - EXIT INT TERM ERR
  set +e
  restore_running_state || { echo "WARNING: could not fully restore the original service state" >&2; [ "${rc}" -eq 0 ] && rc=1; }
  if [ "${completed}" -ne 1 ]; then
    [ "${rc}" -eq 0 ] && rc=1
    if [ "${KEEP_PARTIAL:-0}" = "1" ]; then
      echo "BACKUP FAILED. Incomplete files kept in ${partial} (NOT a valid backup)." >&2
    else
      rm -rf "${partial}"
      echo "BACKUP FAILED. Incomplete files removed." >&2
    fi
  fi
  exit "${rc}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'echo "error on line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

retention="${BACKUP_RETENTION_DAYS:-$(env_value BACKUP_RETENTION_DAYS)}"
if [ -n "${retention}" ] && ! [[ "${retention}" =~ ^[1-9][0-9]*$ ]]; then
  echo "BACKUP_RETENTION_DAYS must be a positive integer (got '${retention}')" >&2; exit 2
fi

[ -e "${final}" ] && { echo "${final} already exists" >&2; exit 1; }
mkdir -p "${partial}/minio"

capture_running_state
quiesce_writers

echo "dumping mysql..."
compose exec -T mysql sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --triggers --events --set-gtid-purged=OFF --add-drop-database --databases storyteller' \
  | gzip > "${partial}/mysql-storyteller.sql.gz"

echo "mirroring minio buckets: ${BUCKETS[*]}"
compose run --rm --no-deps -v "${partial}/minio:/backup" minio-init \
  'set -e; mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null; for b in '"${BUCKETS[*]}"'; do mkdir -p "/backup/$b"; mc mirror --quiet "local/$b" "/backup/$b"; done'

cp "${ROOT_DIR}/UPSTREAM.lock" "${partial}/"
{
  echo "created_utc=${ts}"
  echo "upstream_sha=$(lock_value UPSTREAM_SHA)"
  echo "running_services=${ORIG_RUNNING[*]:-}"
  echo "buckets=${BUCKETS[*]}"
} > "${partial}/MANIFEST"
# SHA256SUMS is explicitly excluded from the input file list.
# shellcheck disable=SC2094
( cd "${partial}" && find . -type f ! -name SHA256SUMS | sort | while IFS= read -r f; do sha256_create "$f"; done > SHA256SUMS )

mv "${partial}" "${final}"
completed=1
echo "backup written to ${final}"

if [ -n "${retention}" ]; then
  echo "pruning completed backups older than ${retention} days"
  while IFS= read -r d; do
    # Only completed backups (timestamp name + SHA256SUMS); never .partial dirs, never the one just written.
    [[ "$(basename "${d}")" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || continue
    [ -f "${d}/SHA256SUMS" ] || continue
    [ "${d}" = "${final}" ] && continue
    echo "deleting ${d}"
    rm -rf "${d}"
  done < <(find "${backups_dir}" -mindepth 1 -maxdepth 1 -type d -mtime "+${retention}")
else
  echo "retention disabled (BACKUP_RETENTION_DAYS unset): no backups deleted"
fi
