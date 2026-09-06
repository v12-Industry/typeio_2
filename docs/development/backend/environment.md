# Environment

"Environment" here means the small set of system-level resources the
whole app runs on — config, a logger, a database connection pool — that
exist exactly once, get acquired at startup, and get threaded down into
everything else. It is **not** where domain/business dependencies live;
that's [Containers](containers.md). This doc covers the raw resources;
Containers covers how they get reshaped into what individual handlers
need.

## `Env`

```haskell
-- Environment.Env
data Env = Env
  { appConf :: AppConfig
  , logger  :: EntryLog
  , pool    :: ConnectionPool
  }

withEnv :: AppConfig -> (Env -> IO r) -> IO r
withEnv cfg = runContT $
  Env cfg <$> withLogger <*> withPool (dbConf cfg)
```

Three resources, acquired once, for the lifetime of the process:

- `appConf :: AppConfig` — already-loaded, already-validated
  configuration (see below). Not acquired via `ContT`; it's pure data,
  loaded before `withEnv` runs (`Platform.Web.main`).
- `logger :: EntryLog` — from `Environment.Logging.withLogger`, a
  `TimedFastLogger` writing structured JSON to stdout. See
  [logging.md](logging.md).
- `pool :: ConnectionPool` — from `Environment.Db.withPool`, a
  `persistent` connection pool, itself wrapped so every query it runs is
  logged as structured JSON — via a *second*, independent logger from
  the one above, not the same `EntryLog` (see [logging.md](logging.md),
  which covers both pipelines and why they're separate).

`withEnv` composes these with `ContT`, which is why `withLogger` and
`withPool` are themselves `ContT r IO EntryLog` / `ContT r IO
ConnectionPool` rather than plain `IO` actions — `ContT` gives
bracket-style acquire/release (the fast-logger and the connection pool
both need cleanup on shutdown) without hand-writing nested `bracket`
calls. `Container.Build.withRootContainer` continues the same `ContT`
chain one level further to build the [Containers](containers.md) from
this `Env`.

## Config

`AppConfig` (`Config.App`) bundles `EnvironmentName` (`Local` /
`Development` / `Production`), `DbConfig` (`Config.Db`), `WebConfig`
(`Config.Web`), and `Visualization` (`Config.Visualization`) — each
loaded from its own set of environment variables (`DB_HOST`, `DB_PORT`,
`WEB_REQUEST_ID_HEADER`, etc. — see `.env` for the full list) via
`lookupEnv`, never hardcoded. `WEB_PORT` is the one exception with a
default (`3000`, see `Config.Web.defaultWebPort`) rather than being
required.

**There is no environment variable for the dependency-graph
visualization.** `GRAPH_VISUALIZATION` existed between #215 and #223 and
is gone: which drawing to render is a property of a *request* now, not
of the process, chosen by an optional `visualizationMode` query
parameter. Delete the line if an old `.env` still has it — nothing reads
it, and leaving it there suggests it does something.

See
[`../../architecture/visualization-switching.md`](../../architecture/visualization-switching.md)
for the mechanism, including why an *absent* parameter takes a default
while an *unrecognised* one is an error.

Validation is accumulating, not fail-fast: each field is checked
independently (present, non-empty, parses, in range) and any failure is
recorded, so `loadConfig` either returns a fully valid `AppConfig` or
raises with **every** missing/invalid variable listed at once — not just
the first one it happened to check.

## What used to be here: `Environment.Acquire`

There used to be an `Environment.Acquire` module (`Acquire`, `Acquire2`)
— an earlier, more elaborate attempt at the same acquire/release problem
`withEnv` solves with plain `ContT`. It had no callers anywhere in the
codebase and was removed in #15.
