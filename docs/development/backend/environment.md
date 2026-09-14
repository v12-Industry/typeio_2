# Environment

"Environment" here means the small set of system-level resources the
whole app runs on — config, a logger, a database connection pool, the
commit the process is running — that exist exactly once, get acquired at
startup, and are then available to every handler. It is the *only* place a handler's dependencies come
from: there is no injection layer between a route and the code answering
it — see [handlers.md](handlers.md).

## `Env`

```haskell
-- App.Env
data Env = Env
  { envConfig :: AppConfig
  , envLogger :: EntryLog
  , envPool   :: ConnectionPool
  , envBuild  :: BuildInfo
  }

withEnv :: AppConfig -> (Env -> IO a) -> IO a
withEnv cfg =
  runContT $
    Env cfg
      <$> withLogger
      <*> withPool (dbConf cfg)
      <*> liftIO loadBuildInfo
```

Four resources, acquired once, for the lifetime of the process:

- `envConfig :: AppConfig` — already-loaded, already-validated
  configuration (see below). Not acquired via `ContT`; it's pure data,
  loaded before `withEnv` runs (`App.Server.main`).
- `envLogger :: EntryLog` — from `Environment.Logging.withLogger`, a
  `TimedFastLogger` writing structured JSON to stdout. See
  [logging.md](logging.md).
- `envPool :: ConnectionPool` — from `Environment.Db.withPool`, a
  `persistent` connection pool, itself wrapped so every query it runs is
  logged as structured JSON — via a *second*, independent logger from
  the one above, not the same `EntryLog` (see [logging.md](logging.md),
  which covers both pipelines and why they're separate).
- `envBuild :: BuildInfo` — from `Platform.Build.loadBuildInfo`, the
  commit `GET /healthz` and `GET /api/system/config` report. See
  [the build commit](#the-build-commit) below. Like `envConfig` it is
  pure data rather than a `ContT`-acquired resource, resolved as
  `withEnv` runs and never read again.

`withEnv` composes these with `ContT`, which is why `withLogger` and
`withPool` are themselves `ContT r IO EntryLog` / `ContT r IO
ConnectionPool` rather than plain `IO` actions — `ContT` gives
bracket-style acquire/release (the fast-logger and the connection pool
both need cleanup on shutdown) without hand-writing nested `bracket`
calls.

## How a handler reaches it

`AppM` is `ReaderT Env Handler`, and `App.Server` lowers it into
Servant's own `Handler` once, at the top, with `hoistServer` (see
[routing.md](routing.md#the-server)). So a handler reads the environment
the ordinary way:

```haskell
runDb :: ReaderT SqlBackend IO a -> AppM a
runDb q = do
  pl <- asks envPool
  liftIO (runSqlPool q pl)
```

`envLogger` is the exception: nothing in `AppM` reads it. It is there for
the [middleware](logging.md), which is composed around the application
rather than inside it.

## The build commit

`Platform.Build.loadBuildInfo` resolves the commit **at process start**,
taking the first of these that yields a full 40-character hash:

1. `BUILD_COMMIT` from the environment — for a binary running away from
   its checkout, where the commit has to be injected by whatever built
   it. It wins over the checkout, because a checkout the binary was not
   built from has no claim on the answer.
2. What `rev-parse HEAD` reports for the working directory the process
   was started in.

Neither of them, or a value that is not a full hash (an abbreviated one,
a branch name, a tag), gives `Platform.Build.unknownCommit` — the string
`UNKNOWN`. The endpoint exists to name one exact commit, so where there
is no exact commit to name, saying so is the answer; a
plausible-looking wrong hash is worse than none.

Resolving at startup rather than capturing the hash at compile time is
what keeps the value honest. `cabal build all` decides up-to-dateness per
*package*, from the content of the sources, so a hash baked in by a
Template Haskell splice survives a `HEAD` that has since moved — the
binary is genuinely current and the commit it reports is not.

## Config

`AppConfig` (`Config.App`) bundles `EnvironmentName` (`Local` /
`Development` / `Production`), `DbConfig` (`Config.Db`) and `WebConfig`
(`Config.Web`) — each loaded from its own set of environment variables
(`DB_HOST`, `DB_PORT`, `WEB_REQUEST_ID_HEADER`, etc. — see `.env` for
the full list) via `lookupEnv`, never hardcoded. `WEB_PORT` is the one exception with a
default (`3000`, see `Config.Web.defaultWebPort`) rather than being
required. That number is duplicated in `make seed-db`, which falls back
to the same `3000` when `WEB_PORT` is unset — changing one without the
other leaves the seed target posting at a port nothing is listening on.

Which dependency-graph drawing to render is **not** among them: it is a
property of a *request*, not of the process — an optional
`visualizationMode` query parameter.

See
[`../../architecture/visualization-switching.md`](../../architecture/visualization-switching.md)
for the mechanism, including why an *absent* parameter takes a default
while an *unrecognised* one is an error.

Validation is accumulating, not fail-fast: each field is checked
independently (present, non-empty, parses, in range) and any failure is
recorded, so `loadConfig` either returns a fully valid `AppConfig` or
raises with **every** missing/invalid variable listed at once — not just
the first one it happened to check.
