#!/bin/bash
#
# Validates migrations/ as a set, then exercises them against a real
# Postgres: up to the newest version, all the way back down to nothing,
# and up again.
#
# The second `up` is the point of the whole thing. A `.down.sql` that
# leaves a stray constraint, sequence or type behind passes a one-way
# `migrate up` and a one-way `migrate down` and only fails when someone
# rolls back and rolls forward again -- which is exactly what a
# developer does when a migration needs another pass, and what nothing
# else in CI covers: the integration and E2E suites apply the up
# migrations to a fresh container and never roll anything back.
#
# Runs against a disposable Postgres container it starts and removes
# itself, so it cannot touch a developer's own database. Pass
# MIGRATION_TEST_DB_URL to point it at one that is already disposable
# (CI's service container) and it will skip the container entirely.
#
# Needs: the `migrate` CLI, plus Docker unless MIGRATION_TEST_DB_URL is
# set.

set -euo pipefail

MIGRATIONS_DIR="${MIGRATIONS_DIR:-migrations}"
CONTAINER_NAME="typeio_migration_test_$$"
CONTAINER_STARTED=""

fail() {
  echo "❌ $1" >&2
  exit 1
}

cleanup() {
  if [ -n "$CONTAINER_STARTED" ]; then
    docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

command -v migrate > /dev/null 2>&1 ||
  fail "the 'migrate' CLI is not on PATH (https://github.com/golang-migrate/migrate)"

# --- The files, before any database is involved ---------------------
#
# A migration with no partner, or a gap in the sequence, is a fault the
# database cannot report: `migrate up` is perfectly happy to apply 1, 2
# and 4, and an absent .down.sql only shows up the day someone needs it.

echo "▶ Checking migration files"

ups=$(find "$MIGRATIONS_DIR" -name '*.up.sql' | sort)
[ -n "$ups" ] || fail "no .up.sql files found in $MIGRATIONS_DIR"

expected=1
newest=0
for up in $ups; do
  down="${up%.up.sql}.down.sql"
  [ -f "$down" ] || fail "$up has no matching $(basename "$down")"

  version=$(basename "$up" | cut -d_ -f1)
  case "$version" in
    ''|*[!0-9]*) fail "$up does not start with a numeric version" ;;
  esac

  numeric=$((10#$version))
  [ "$numeric" -eq "$expected" ] ||
    fail "expected migration $expected next, found $numeric ($up) -- the sequence has a gap or a duplicate"

  expected=$((expected + 1))
  newest=$numeric
done

echo "  $newest migrations, each with a down, numbered without gaps"

# --- A database to run them against ---------------------------------

if [ -n "${MIGRATION_TEST_DB_URL:-}" ]; then
  db_url="$MIGRATION_TEST_DB_URL"
  echo "▶ Using the database given in MIGRATION_TEST_DB_URL"
else
  command -v docker > /dev/null 2>&1 ||
    fail "Docker is not available, and MIGRATION_TEST_DB_URL is not set"

  echo "▶ Starting a disposable Postgres"
  docker run --rm -d \
    --name "$CONTAINER_NAME" \
    -e POSTGRES_USER=typeio_migration \
    -e POSTGRES_PASSWORD=typeio_migration \
    -p 5432 \
    postgres:15 > /dev/null
  CONTAINER_STARTED=1

  port=$(docker port "$CONTAINER_NAME" 5432/tcp | head -1 | sed 's/.*://')
  [ -n "$port" ] || fail "could not find the disposable Postgres's published port"

  ready=""
  for _ in $(seq 1 30); do
    if docker exec "$CONTAINER_NAME" pg_isready -U typeio_migration -d typeio_migration > /dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done
  [ -n "$ready" ] || fail "the disposable Postgres did not become ready in time"

  db_url="postgres://typeio_migration:typeio_migration@localhost:$port/typeio_migration?sslmode=disable"
fi

run_migrate() {
  migrate -path "$MIGRATIONS_DIR" -database "$db_url" "$@"
}

# `migrate version` prints the version on stderr, appends "(dirty)" when
# a migration failed part-way through and left the schema in a state
# nothing can safely apply to, and exits non-zero when nothing is
# applied at all -- which is a perfectly good answer here rather than a
# failure, so the status is swallowed and the caller reads the text.
current_version() {
  run_migrate version 2>&1 || true
}

expect_version() {
  local expected_version="$1"
  local label="$2"
  local reported
  reported=$(current_version)

  case "$reported" in
    *dirty*) fail "$label: the schema is dirty ($reported)" ;;
  esac

  [ "$reported" = "$expected_version" ] ||
    fail "$label: expected version $expected_version, got '$reported'"
}

# --- Up, down, and up again -----------------------------------------

echo "▶ Applying every migration"
run_migrate up
expect_version "$newest" "after up"

echo "▶ Rolling every migration back"
run_migrate down -all
reported=$(current_version)
case "$reported" in
  *"no migration"*) ;;
  *) fail "after down: expected no migration to be applied, got '$reported'" ;;
esac

echo "▶ Applying every migration again, onto what down left behind"
run_migrate up
expect_version "$newest" "after the second up"

echo "✅ Migrations apply, roll back, and re-apply cleanly"
