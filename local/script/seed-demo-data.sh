#!/bin/bash

set -e

# Loads the demo projects (local/sql/demo-data.sql) straight into
# Postgres. Deliberately outside the app: the web app seeds the
# reference rows it needs to operate and nothing else, so fixture data
# is applied here, against the database, with the app uninvolved.
#
# Talks to the database two ways, preferring the container because that
# is what the local setup runs: `docker exec` into $CONTAINER_NAME when
# a container by that name is up, otherwise `psql` on PATH against
# DB_HOST/DB_PORT.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
sql_file="$repo_root/local/sql/demo-data.sql"
env_file="$repo_root/.env"

if [ -f "$env_file" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
fi

CONTAINER_NAME="${CONTAINER_NAME:-typeio_db}"
DB_USER="${DB_USER:-postgres}"
DB_DATABASE="${DB_DATABASE:-project}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

if [ ! -f "$sql_file" ]; then
  echo "❌ $sql_file not found"
  exit 1
fi

echo "🌱 Seeding demo projects..."

if command -v docker > /dev/null 2>&1 &&
  docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  docker exec -i "$CONTAINER_NAME" \
    psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_DATABASE" < "$sql_file"
elif command -v psql > /dev/null 2>&1; then
  PGPASSWORD="$DB_PASS" psql -v ON_ERROR_STOP=1 \
    -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_DATABASE" \
    -f "$sql_file"
else
  echo "❌ No way to reach Postgres: no container named $CONTAINER_NAME is"
  echo "   running, and psql is not on PATH."
  exit 1
fi

echo "✅ Demo projects seeded"
