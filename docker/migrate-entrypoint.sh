#!/usr/bin/env bash
# 1) Applies upstream diesel migrations (_database/sql/migrations) to MySQL.
#    Upstream reference: _docs/dev_setup_server.md ("diesel migration run"), diesel.toml.
# 2) Seeds upstream system roles (user/mod/admin) ONLY when user_roles is empty.
#    Why: new accounts get user_role_slug='user'
#      (crates/schema/database/mysql_queries/src/queries/users/user/create/create_account_generic.rs:100,135,176).
#    Session queries LEFT JOIN user_roles and default missing permissions to false
#      (.../users/user_sessions/get_user_session_by_token.rs:168,212-232), so login works without the
#      seed, but users then have no role permissions (e.g. can_delete_own_account).
#    Upstream seed _database/sql/seed/sql/system_roles.sql uses plain INSERT and user_roles.slug is UNIQUE
#      (_database/sql/migrations/2021-05-15-071534_users/up.sql:201), so re-running it would fail.
#      We therefore apply it only on an empty table, inside one transaction.
#    Badges (user_badges.sql) are legacy and not needed; use scripts/seed.sh manually if wanted.
set -Eeuo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"
echo "upstream sha: $(cat /GIT_SHA)"
cd /app
diesel migration run --database-url "${DATABASE_URL}" --migration-dir /app/_database/sql/migrations
echo "migrations complete"
diesel migration list --database-url "${DATABASE_URL}" --migration-dir /app/_database/sql/migrations | tail -n 5

if [ "${AUTO_SEED_ROLES:-true}" = "true" ]; then
  : "${SEED_DB_HOST:?SEED_DB_HOST is required for role seeding}"
  : "${SEED_DB_USER:?SEED_DB_USER is required for role seeding}"
  : "${MYSQL_PWD:?MYSQL_PWD is required for role seeding}"
  mysql_cmd=(mysql -h "${SEED_DB_HOST}" -u "${SEED_DB_USER}" --batch --skip-column-names storyteller)
  count="$("${mysql_cmd[@]}" -e 'SELECT COUNT(*) FROM user_roles')"
  if [ "${count}" = "0" ]; then
    echo "user_roles is empty: applying upstream _database/sql/seed/sql/system_roles.sql in one transaction"
    { echo 'START TRANSACTION;'; cat /app/_database/sql/seed/sql/system_roles.sql; echo; echo 'COMMIT;'; } \
      | "${mysql_cmd[@]}"
    echo "roles now: $("${mysql_cmd[@]}" -e 'SELECT GROUP_CONCAT(slug ORDER BY slug) FROM user_roles')"
  else
    echo "user_roles already has ${count} row(s): skipping role seed"
  fi
else
  echo "AUTO_SEED_ROLES=${AUTO_SEED_ROLES}: skipping role seed"
fi
