# Logging

There are **two independent logging pipelines** in this app, not one
shared logger used everywhere. Both write structured JSON to stdout via
[`fast-logger`](https://hackage.haskell.org/package/fast-logger), but
they're separate instances set up for different reasons, and it's worth
knowing that going in so you don't go looking for one shared logger
object that doesn't exist.

## Pipeline 1: request/response logging

The app's own logger, built once at startup:

```haskell
-- Environment.Logging
withLogger :: ContT r IO EntryLog
withLogger = toEntryLog <$> ContT (withTimedFastLogger getFormattedTime (LogStdout 10))
```

`EntryLog` (`Logging.Core`) is a newtype wrapping one function,
`runEntryLog :: ToJSON a => LogSource -> LogLevel -> a -> IO ()`, that
wraps whatever you give it in a `JsonLog { message, level, source,
timestamp }` envelope and pushes it through the shared
`TimedFastLogger`. `Logging.Core.LogLevel` (`Debug | Info | Warning |
Error`) is this app's own type — see the gotcha below.

Two middleware, both built from the same `EntryLog`, log one entry each
per request:

- `Domain.System.Middleware.Logging.Request.requestLogMiddleware` — logs
  a `RequestLog` (`method`, `path`, `headers`, `requestId`) before
  calling the wrapped `Application`, tagged with source `"Web"`.
- `Domain.System.Middleware.Logging.Response.responseLogMiddleware` —
  logs a `ResponseLog` (`headers`, `requestId`, `status`) from inside the
  response callback, after the app has produced a response, tagged with
  source `"ResponseLog"` (the two middleware don't use a consistent
  source-name convention — worth normalizing if you're touching either).

The two are correlated by a request id, not nesting: earlier in the
pipeline, `Domain.System.Middleware.RequestId.requestIdMiddleware`
generates a UUID and injects it as a request header (whatever
`WEB_REQUEST_ID_HEADER` names), *before* either logging middleware runs.
Both middleware just read that header back out — request and response
logs for the same request share the same `requestId` value in their JSON
output, which is what makes them joinable in whatever reads the logs.
Ordering matters here: `RequestId` has to run before the two logging
middleware in `App.Middleware`'s pipeline, or there's no header
yet for them to read.

Both `Request`/`Response` share one small helper,
`Domain.System.Middleware.Logging.Common.hashMapHeaders`, to turn WAI's
`RequestHeaders` into a plain `HashMap String String` for JSON encoding.

## Pipeline 2: database query logging

Persistent/esqueleto require a `MonadLogger`/`MonadLoggerIO` instance to
run queries at all — `Logging.Database.DatabaseLoggingT` exists to
satisfy that, and it does **not** reuse `EntryLog`:

```haskell
runDatabaseLoggingT :: MonadIO m => DatabaseLoggingT m a -> m a
runDatabaseLoggingT action = do
  loggerSet <- liftIO $ newStdoutLoggerSet defaultBufSize
  runReaderT (unDatabaseLoggingT action) loggerSet
```

It creates its own `fast-logger` `LoggerSet` and implements
`MonadLogger`'s `monadLoggerLog` to JSON-encode each query as a
`DatabaseLog { message, level, source, timestamp }` and push it to that
logger. This is wired in exactly once, in `Environment.Db.withPool`:

```haskell
with' k =
  runDatabaseLoggingT $
    withPostgresqlPoolWithConf c h
    $ liftIO . k
```

so every query run against the pool for the life of the process goes
through this same `DatabaseLoggingT`/`LoggerSet` — but it's a second,
independent stdout JSON logger, not the `EntryLog` from Pipeline 1. The
practical effect is the same (structured JSON lines on stdout) but if you
ever need to change log destinations/formatting, there are two places to
change, not one.

## Gotcha: two unrelated `LogLevel` types

`Logging.Core` defines its own `LogLevel` (`Debug | Info | Warning |
Error`) for pipeline 1. `Logging.Database` imports a *different*
`LogLevel` from `Control.Monad.Logger` (the `monad-logger` package's
type, e.g. `LevelDebug`/`LevelInfo`/...) for pipeline 2, because that's
what `MonadLogger`'s interface requires. Both are just called `LogLevel`
in their respective modules — double-check which one you're importing if
you're adding a log call, since the wrong one will still type-check in
plenty of contexts and just be the wrong level type.

(`DatabaseLog`'s `ToJSON` instance turns `Control.Monad.Logger`'s
`LevelInfo`-style constructor names into lowercase short names —
`drop 5 . show` strips the `"Level"` prefix, then lowercases — so `info`/
`debug`/`warn`/`error` appear in the JSON output rather than the
constructor names verbatim.)
