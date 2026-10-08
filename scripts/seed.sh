#!/usr/bin/env bash
# shellcheck disable=SC2016 # single quotes intentional: vars expand inside containers
# OPTIONAL, manual: apply upstream legacy badge seed (_database/sql/seed/sql/user_badges.sql).
# System roles are already seeded automatically by the migrate one-shot (docker/migrate-entrypoint.sh).
# The upstream seed uses plain INSERT (not idempotent), so this only runs when the badges table is empty.
# Requires ./upstream (scripts/fetch-upstream.sh) and a running mysql service.
set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
seed_file="${ROOT_DIR}/upstream/_database/sql/seed/sql/user_badges.sql"
[ -f "${seed_file}" ] || { echo "run scripts/fetch-upstream.sh first" >&2; exit 1; }
mysql_q() { compose exec -T mysql sh -c 'exec mysql -ustoryteller -p"$MYSQL_PASSWORD" --batch --skip-column-names storyteller'; }
count="$(echo 'SELECT COUNT(*) FROM badges;' | mysql_q)"
if [ "${count}" != "0" ]; then
  echo "badges already has ${count} row(s); skipping (upstream seed is not idempotent)"
  exit 0
fi
echo "applying user_badges.sql in one transaction"
{ echo 'START TRANSACTION;'; cat "${seed_file}"; echo; echo 'COMMIT;'; } | mysql_q
echo "done"
