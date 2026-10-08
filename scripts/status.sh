#!/usr/bin/env bash
# Show container health and probe the API health route (GET /_status, upstream http_server/routes/service_routes.rs:26)
# directly and through the webapp origin (nginx /v1 + /_status proxy).
set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
port="$(env_value API_PORT)"; port="${port:-12345}"
wport="$(env_value WEBAPP_PORT)"; wport="${wport:-4201}"
compose ps
echo
rc=0
if curl -fsS "http://127.0.0.1:${port}/_status"; then echo; echo "storyteller-web: OK"; else echo "storyteller-web: NOT healthy (docker compose logs storyteller-web)" >&2; rc=1; fi
if curl -fsS -o /dev/null "http://127.0.0.1:${wport}/" && curl -fsS -o /dev/null "http://127.0.0.1:${wport}/_status"; then
  echo "webapp (http://localhost:${wport}): OK"
else
  echo "webapp: NOT healthy (docker compose logs webapp)" >&2; rc=1
fi
exit "${rc}"
