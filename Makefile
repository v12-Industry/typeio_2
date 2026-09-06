## .env is gitignored, so a fresh clone or git worktree has none. A hard
## `include` would make every target fail before make even looks at the
## one you asked for -- including format/format-check/test, which need
## nothing from it. Targets that do need the database variables guard
## for themselves via check-db-env below.
-include .env
export

# --- Config ---
CONTAINER_NAME=typeio_db
DB_URL=postgres://$(DB_USER):$(DB_PASS)@$(DB_HOST):$(DB_PORT)/$(DB_DATABASE)?sslmode=disable
MIGRATE=migrate
MIGRATIONS_DIR=migrations

# --- Commands ---
.PHONY: check-db-env migrate-up migrate-down migrate-new migrate-force migrate-down-all migrate-version start-app test test-integration test-e2e e2e-install format format-check

## Fail early, and legibly, when the database variables are missing.
## Without this, DB_URL still interpolates -- into
## postgres://:@:/?sslmode=disable -- and `migrate` reports a connection
## failure that says nothing about the actual cause.
check-db-env:
	@if [ -z "$(DB_USER)" ] || [ -z "$(DB_HOST)" ] || [ -z "$(DB_PORT)" ] || [ -z "$(DB_DATABASE)" ]; then \
		echo "The database variables are not set."; \
		echo "They come from .env, which is gitignored -- a fresh clone or"; \
		echo "git worktree has none. Run: cp .env.example .env"; \
		exit 1; \
	fi

## Run migratin tests
test-migrations:
	./scripts/test-migrations.sh

## Format all Haskell source files in place with Fourmolu (fourmolu.yaml
## at the repo root). Also what the PostToolUse hook in
## .claude/settings.json and HLS's formattingProvider run on save --
## this target exists so CI/pre-commit and humans/agents share one
## command.
format:
	fourmolu --mode inplace $$(find lib exe test test-integration -name '*.hs')

## Check that every Haskell source file is already Fourmolu-formatted,
## without modifying anything -- non-zero exit on any diff. CI-friendly
## counterpart to `format`.
format-check:
	fourmolu --mode check $$(find lib exe test test-integration -name '*.hs')

## Run postgres container
run-postgres:
	./local/script/start-postgres.sh $(CONTAINER_NAME)

## Echo back the database URL
print-db-url: check-db-env
	@echo $(DB_URL)

## Apply all up migrations
migrate-up: check-db-env
	$(MIGRATE) -path $(MIGRATIONS_DIR) -database "$(DB_URL)" up

## Roll back last migration
migrate-down: check-db-env
	$(MIGRATE) -path $(MIGRATIONS_DIR) -database "$(DB_URL)" down 1

## Show current migration version
migrate-version: check-db-env
	$(MIGRATE) -path $(MIGRATIONS_DIR) -database "$(DB_URL)" version

## Force migration to a specific version: make migrate-force VERSION=2
migrate-force: check-db-env
	$(MIGRATE) -path $(MIGRATIONS_DIR) -database "$(DB_URL)" force $(VERSION)

## Roll back to 0
migrate-down-all: check-db-env
	$(MIGRATE) -path $(MIGRATIONS_DIR) -database "$(DB_URL)" down

## Create a new migration file: make migrate-new NAME=add_table
migrate-new:
	$(MIGRATE) create -ext sql -dir $(MIGRATIONS_DIR) -seq $(NAME)

## run program to seed database
seed-db:
	curl --location --request POST 'localhost:$(or $(WEB_PORT),3000)/api/central/seed-database'

## Start Postgres, apply migrations, start the app in the background,
## wait for it to be ready, then seed it -- one command in place of
## run-postgres/migrate-up/cabal run server/seed-db run by hand across
## separate terminals. Keeps running afterward (logs at
## local/server.log) until Ctrl+C, which stops the backgrounded server
## cleanly -- no orphaned process left behind.
start-app:
	./local/script/start-app.sh

## Run the Haskell unit test suite
test:
	cabal test spec

## Run the Haskell integration test suite (needs Docker -- starts and
## tears down its own disposable, already-migrated Postgres via
## testcontainers, no manually-started database or `migrate` CLI
## required)
test-integration:
	cabal test integration

## Install the E2E suite's dependencies (Playwright + Chromium). One-time
## setup, or re-run after e2e/package.json changes.
e2e-install:
	cd e2e && npm install && npx playwright install --with-deps chromium

## Run the E2E test suite. Unlike test/test-integration, this doesn't
## start its own database or server -- needs a real app already running
## against a real, migrated + seeded Postgres (run-postgres, migrate-up,
## `cabal run server` in another terminal, then seed-db -- or just
## `make start-app`). See e2e/README.md for the full sequence and how to
## run it headed/in UI mode to watch it drive a browser.
test-e2e:
	cd e2e && npm test
