#!/usr/bin/env bash
# shellcheck disable=SC2016 # single quotes intentional: vars expand inside containers
# Run on a REAL running stack. Verifies MinIO anonymous access is exactly:
#   - private buckets (artcraft-private, artcraft-public-gc): no anonymous read or list
#   - artcraft-public: anonymous GetObject under media/ only; no ListBucket; nothing outside media/
#   - the webapp origin serves /media/<key> from the public bucket
# Uploads two small test objects with admin credentials (inside the minio-init container) and
# always deletes them again. Exit 1 if any expectation fails.
set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
minio_port="$(env_value MINIO_API_PORT)"; minio_port="${minio_port:-9000}"
webapp_port="$(env_value WEBAPP_PORT)"; webapp_port="${webapp_port:-4201}"
S3="http://127.0.0.1:${minio_port}"
WEB="http://127.0.0.1:${webapp_port}"
id="policy-check-$(date -u +%Y%m%dT%H%M%SZ)-$$"
in_key="media/_policy_check/${id}.txt"
out_key="_policy_check/${id}.txt"
fails=0

mc_run() { compose run --rm --no-deps -T minio-init "mc alias set local http://minio:9000 \"\$MINIO_ROOT_USER\" \"\$MINIO_ROOT_PASSWORD\" >/dev/null && $1"; }
cleanup() {
  set +e
  mc_run "mc rm --quiet local/artcraft-public/${in_key} local/artcraft-public/${out_key} local/artcraft-private/${out_key}" >/dev/null 2>&1
}
trap cleanup EXIT

expect() { # $1 description, $2 expected HTTP code, $3 url
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' "$3" || echo 000)"
  if [ "${code}" = "$2" ]; then echo "ok   ${code}  $1"; else echo "FAIL ${code} (expected $2)  $1"; fails=1; fi
}

echo "uploading test objects (admin credentials, inside container)..."
mc_run "echo ok | mc pipe --quiet local/artcraft-public/${in_key} && echo ok | mc pipe --quiet local/artcraft-public/${out_key} && echo ok | mc pipe --quiet local/artcraft-private/${out_key}" >/dev/null

expect "public bucket: anonymous GetObject under media/"        200 "${S3}/artcraft-public/${in_key}"
expect "public bucket: anonymous GetObject outside media/"      403 "${S3}/artcraft-public/${out_key}"
expect "public bucket: anonymous ListBucket"                    403 "${S3}/artcraft-public/?list-type=2"
expect "public bucket: anonymous ListBucket with media/ prefix" 403 "${S3}/artcraft-public/?list-type=2&prefix=media/"
expect "private bucket: anonymous GetObject"                    403 "${S3}/artcraft-private/${out_key}"
expect "private bucket: anonymous ListBucket"                   403 "${S3}/artcraft-private/?list-type=2"
expect "gc bucket: anonymous ListBucket"                        403 "${S3}/artcraft-public-gc/?list-type=2"
expect "webapp origin: /media/ proxied to public bucket"        200 "${WEB}/${in_key}"
expect "webapp origin: missing media object"                    404 "${WEB}/media/_policy_check/does-not-exist-${id}.txt"

if [ "${fails}" -ne 0 ]; then echo "storage policy check: FAILED"; exit 1; fi
echo "storage policy check: passed"
