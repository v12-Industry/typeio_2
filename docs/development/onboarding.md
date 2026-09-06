# Developer Onboarding

Start here. This page gets you running locally, then walks one request
through the whole app so the rest of `docs/development/` has somewhere to
hang off of.

## Prerequisites

- GHC + `cabal`, via [ghcup](https://www.haskell.org/ghcup/).
- Docker, for PostgreSQL.
- A `.env` file at the repo root (see the keys `Config.App`/`Config.Db`/
  `Config.Web` look up — `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USER`,
  `DB_PASS`, `DB_POOL_COUNT`, `DB_SCHEMA`, `ENV`,
  `WEB_INDEX_REDIRECT`, `WEB_REQUEST_ID_HEADER`). Loading is silently
  best-effort (`Platform.Web.loadDotEnv` swallows a missing file), but
  the app will fail fast at startup with every missing/invalid variable
  listed at once if any of these aren't actually set — see
  [`backend/environment.md`](backend/environment.md). `WEB_PORT` is the
  one exception: it's optional and defaults to `3000` if unset (see
  `Config.Web.defaultWebPort`).

## Getting it running

The one-command path — starts Postgres, applies migrations, builds and
starts the app in the background, waits for it to be ready, then seeds
it:

```
cabal build all    # build everything
make start-app
```

`make start-app` keeps running afterward (server logs at
`local/server.log`) until you Ctrl+C it, which stops the backgrounded
server cleanly. See the `Makefile` (`start-app` target) and
`local/script/start-app.sh` for what it's doing under the hood.

Or run the same steps by hand, one command per terminal — useful if you
want a piece of this running on its own:

```
make run-postgres      # start Postgres in Docker
make migrate-up        # apply all migrations
cabal build all        # build everything
cabal run server        # start the app, reads .env
make seed-db           # reference data + a demo project (needs the server already running)
```

Once it's running, visit `http://localhost:3000` (or whatever `WEB_PORT`
is set to) in a browser.

`make seed-db` inserts the reference data (`NodeStatus`/`NodeType`) and
a demo project, **Public API launch**, with seven work nodes and real
dependencies between them. It is idempotent — running it twice leaves
one demo project.

The demo project is there because the seed once inserted
reference data only, and there is still no way to create a dependency
through the UI — so a freshly seeded database drew every graph
as a handful of disconnected nodes with no edges, in every
visualization. Its shape is deliberate: three heads, and one node (the
auth service) that three separate outcomes are waiting on. That shared
bottleneck is what makes the visualizations differ from each other
rather than all looking the same.

Other `make migrate-*` targets (`migrate-down`, `migrate-down-all`,
`migrate-new NAME=...`, `migrate-version`, `migrate-force VERSION=...`)
cover the rest of the migration lifecycle — see the `Makefile`.

**Verifying a change:** `cabal build all` (with `-Wall` on) is the
standard check. A unit suite also exists (`cabal test` / `make test`)
and runs in CI on every PR (see [`ci.md`](ci.md)) — running it locally
first is optional but catches a failure faster than waiting on CI.
`make test-migrations` is currently broken (it calls a script,
`scripts/test-migrations.sh`, that doesn't exist in the repo) — don't
rely on it.

**Formatting** is automated via Fourmolu (`fourmolu.yaml` at the repo
root) — `make format` formats every `.hs` file in place, `make
format-check` checks without modifying anything. Point your editor's
`haskell.formattingProvider` HLS setting at `fourmolu` for format-on-save
(`.vscode/settings.json` already does this for VS Code); Claude Code
picks it up automatically via a `PostToolUse` hook. See
`docs/solution-proposals/haskell-auto-formatting.md` for the rationale.

## How a request flows through the app

Roughly, from `cabal run server` down to a response:

1. **`Platform.Web.main`** loads `.env`, loads and validates config
   (`Config.App`), and acquires the process-lifetime resources —
   config/logger/DB pool — as an `Env` (see
   [`backend/environment.md`](backend/environment.md)).
2. That `Env` is used to build a `RootContainer` — a tree of
   already-wired handler functions, one branch per domain, each split
   into API/UI sub-containers (see
   [`backend/containers.md`](backend/containers.md)).
3. Every request passes through an ordered middleware pipeline
   (`Platform.Web.Middleware`) before routing: a request-id gets tagged
   on, then request logging, then response logging, then the
   index-render middleware (`Domain.Central.Middleware.IndexRender` —
   for a direct/non-htmx request, or an htmx history-restore request, to
   a `ui/.../vw` path, it re-wraps the response in the full `#container`
   shell instead of returning a bare fragment, so a refreshed or
   bookmarked URL still works), then static file serving. Order is
   load-bearing here — request-id has to run before the two logging
   middleware, or they'd have nothing to log (see
   [`backend/logging.md`](backend/logging.md)).
4. **`Platform.Web.Router.routeRequest`** takes what's left, matches the
   request path and method against a hand-built route tree, and pulls
   the specific handler out of the `RootContainer` for that route (see
   [`backend/routing.md`](backend/routing.md)).
5. The handler runs — usually a DB query via esqueleto/persistent (which
   is where the *second* logging pipeline, DB query logging, kicks in;
   also covered in `backend/logging.md`) — and renders `Html ()` via
   Lucid into the HTTP response body (see
   [`ui/haskell-rendering.md`](ui/haskell-rendering.md)).
6. In the browser, that response is usually the result of an
   [htmx](frontend/htmx.md) request swapping into `#container` or a
   narrower target — see [`ui/components.md`](ui/components.md) for what
   `#container`/`#view` are, and [`frontend/hyperscript.md`](frontend/hyperscript.md)
   for the small per-element effects layered on top.

## Where to go next

- [`ui/index.md`](ui/index.md) — the `#container`/`#view` pattern,
  Lucid-as-templating, and global vs. scoped CSS.
- [`frontend/index.md`](frontend/index.md) — htmx and hyperscript.
- [`backend/routing.md`](backend/routing.md),
  [`backend/environment.md`](backend/environment.md),
  [`backend/containers.md`](backend/containers.md),
  [`backend/logging.md`](backend/logging.md) — the bespoke backend stack,
  one concern per file.
- [`ci.md`](ci.md) — what CI runs on a PR, and how to reproduce it
  locally before pushing.
- [`unit-testing.md`](unit-testing.md) — where tests live, how to run
  them, and what's in/out of scope.
- [`integration-testing.md`](integration-testing.md) — the
  Docker-backed suite that covers responders, which the unit suite
  deliberately doesn't.
- [`labels.md`](labels.md) — the `type:*`/`area:*` GitHub issue label
  taxonomy, and when to use each.
- [`release-management.md`](release-management.md) — how to cut a
  release: bumping `typeio.cabal`'s `version:`, and what happens
  automatically once it merges (tag + GitHub Release).
- [`infrastructure.md`](infrastructure.md) — repo-level config (GitHub
  branch protection) managed as OpenTofu + Terragrunt.
- [`../solution-proposals/`](../solution-proposals/) — spikes and
  decisions, e.g. the rationale behind adopting Fourmolu for
  auto-formatting.

## A couple of things that will trip you up

- **Routes match on a path prefix, not an exact path** — see
  [`backend/routing.md`](backend/routing.md) for why.
