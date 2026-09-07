# Solution Proposal: Application Telemetry

- **Status:** Decided — see §6. Implementation tracked in #273.
- **Date:** 2026-09-06
- **Related:** #272 (this spike), #273 (implementation),
  `docs/development/backend/logging.md` (the two pipelines this proposal
  builds on), `docs/development/infrastructure.md` (why GCP is the
  likely eventual cloud target, and why no provider is chosen yet)

## 1. Problem statement

The app has structured logging and nothing else in the telemetry space.
There is no way today to answer "how long did that request take," "is
the error rate climbing," or "where did the last slow request actually
spend its time" — and two decisions that would normally steer a
telemetry choice, a **Grafana** stack and **GCP** as the deploy target,
are both on the horizon without being committed. A recommendation that
assumes either one has a real chance of being wrong within the same
quarter it's written.

## 2. What's actually in place

Confirmed by reading the middleware pipeline and logging modules
directly (`lib/src/Platform/Web/Middleware.hs`,
`Domain.System.Middleware.Logging.*`, `Logging.Database`), not assumed
from `logging.md`:

- **Two independent structured-JSON logging pipelines**, both via
  `fast-logger`, both to stdout — request/response logging and database
  query logging. They don't share a logger instance or a `LogLevel`
  type. See `logging.md` for the full shape; this proposal doesn't
  repeat it.
- **No latency is measured anywhere.** `RequestLog` and `ResponseLog`
  each get their own `timestamp` from the shared `JsonLog` envelope, but
  nothing computes or emits a duration. The two lines *could* be joined
  on `requestId` and diffed by whatever reads the logs downstream — but
  nothing does that today, and nothing in this app hands a reader that
  join for free.
- **An unhandled exception is invisible to the response log.**
  `responseLogMiddleware` logs from inside the `respond` callback
  (`ap req $ \resp -> ...` in `Response.hs`); an exception thrown before
  that callback runs skips the middleware entirely. Warp still answers
  the request with its own default handling, but that path produces no
  structured log line and no `requestId` correlation. A crashing handler
  is currently silent to both pipelines.
- **No metrics of any kind** — no request counters, no status-code
  rates, no GHC RTS stats (GC pauses, memory, live threads).
- **No tracing** — no span across the DB round-trip inside a request, no
  way to see where a slow request actually spent its time.
- **`-rtsopts` is already on** `exe/server`'s `ghc-options` (Warp's
  threaded RTS needs `-threaded`, and `-rtsopts` lets that be
  controlled), **but `-T` is not** — checked by reading
  `typeio.cabal` directly. Any RTS-stats-exposing metrics library needs
  `+RTS -T -RTS` at runtime or `-T` baked into `-with-rtsopts` at
  compile time; today, neither is set, so GC/memory stats aren't
  reachable by anything even if a metrics library were added.
- **No shipped-log destination.** Logs are NDJSON on stdout; whatever
  runs the container is responsible for capturing them, and nothing in
  the repo says what that is — there is no deployment target yet at
  all (see §3).

## 3. The two open horizons

Neither is committed, and the recommendation below is built to survive
either landing differently than expected:

- **GCP.** `infrastructure.md` already calls it "the project's likely
  eventual cloud target" — it's why the OpenTofu state backend is GCS
  rather than HCP Terraform — but **no cloud provider is chosen yet**
  and no deployment target (Cloud Run vs. GKE vs. Compute Engine) exists.
  This matters concretely for telemetry: GCP's automatic
  stdout-to-Cloud-Logging ingestion, and whether Cloud Trace/Cloud
  Monitoring are reachable without extra wiring, both depend on *which*
  compute product ends up hosting this, which isn't decided.
- **Grafana.** Self-hosted vs. Grafana Cloud isn't decided either, and
  doesn't need to be for this proposal to reach a recommendation — both
  read the same wire formats (Prometheus remote-write or scrape,
  OTLP).

The one thing both share: **neither is a wire format.** Prometheus's
exposition format and OpenTelemetry's OTLP are both accepted by
Grafana's stack *and* by GCP (Managed Service for Prometheus, and
Cloud Trace/Cloud Monitoring's OTLP ingestion, respectively) — so the
real decision this proposal has to make isn't "Grafana or GCP," it's
"which wire format to speak," which is answerable now.

## 4. Options considered

All package names below were checked against Hackage before being
named here (`cabal list`), not cited from memory.

### 4.1 Metrics

| Option | Notes |
|---|---|
| `prometheus-client` + `wai-middleware-prometheus` + `prometheus-metrics-ghc` | Exposes a `/metrics` endpoint in Prometheus's own exposition format. Grafana scrapes it natively; GCP's Managed Service for Prometheus also scrapes Prometheus-format endpoints directly, so this is not actually a Grafana-only bet. `prometheus-metrics-ghc` covers the GHC RTS stats gap from §2, once `-T` is enabled. |
| `ekg` / `ekg-core` | In-process, dependency-light, but ships its own bespoke web UI rather than a wire format either backend understands. `ekg-prometheus-adapter` exists to bridge it to Prometheus format, which is strictly more moving parts than emitting Prometheus format directly. **Rejected** — the adapter buys nothing `prometheus-client` doesn't already give for free. |
| OpenTelemetry metrics (`hs-opentelemetry-sdk`) | Same OTLP wire format as tracing below — one SDK, one exporter config, covers metrics and traces together. Heavier to wire up than `prometheus-client` alone for metrics-only use. |

### 4.2 Traces

| Option | Notes |
|---|---|
| `hs-opentelemetry-sdk` + `hs-opentelemetry-instrumentation-wai`, exported via OTLP | The one pillar where instrumenting *now* doesn't require guessing which horizon lands first: Grafana Tempo and Grafana Cloud both accept OTLP directly, and so does GCP Cloud Trace. The exporter is the only thing that changes when the backend is picked — `hs-opentelemetry-exporter-otlp` for a real collector, `hs-opentelemetry-exporter-handle` (stdout) for local dev and for right now, with no collector running anywhere. |
| Nothing (status quo) | Zero cost, but leaves the DB-round-trip-timing gap in §2 permanently unaddressed — there's no other route to "where did this request spend its time" without tracing. **Rejected** as a permanent answer, though it's exactly what today's zero-config state already is. |

### 4.3 Logs

| Option | Notes |
|---|---|
| Keep the two `fast-logger` pipelines, reshape field names | Lowest-risk option. GCP's Cloud Logging agent parses stdout JSON into structured entries when it recognizes fields like `severity`/`message`; Grafana Loki cares less about field names and more about consistent labels. Both are reachable by adjusting what the existing `JsonLog`/`RequestLog`/`ResponseLog`/`DatabaseLog` types already emit, not by replacing the pipeline. |
| Replace with `katip` | A real structured-logging framework with its own scoped-context and severity model. **Rejected for now** — the two existing pipelines already produce structured JSON; the actual gaps (§2's missing latency and invisible exceptions) aren't things `katip` fixes by existing, they're things this app has to compute and log regardless of which logging library holds the pen. Revisit only if the two-pipeline split itself becomes the problem, which it isn't yet. |

## 5. Recommendation

**Adopt OpenTelemetry (`hs-opentelemetry-sdk` +
`hs-opentelemetry-instrumentation-wai`) as the instrumentation layer for
metrics and traces, exported via OTLP, with a stdout exporter
(`hs-opentelemetry-exporter-handle`) until a real collector exists
anywhere to send it to.**

This is the one choice that survives both open horizons: it produces
real metrics and traces today, using OTLP as the wire format both
Grafana's stack and GCP accept without a translation layer, and it
defers "which backend" to exporter configuration rather than to
instrumentation code. Nothing about the WAI instrumentation or the
spans added inside a handler changes when the destination is finally
picked.

**Fix the two gaps from §2 as part of the same work**, independent of
telemetry-stack choice, because both are correctness problems today:

- Compute and log request duration explicitly, rather than leaving it
  as a theoretical join between two timestamps nothing performs.
- Wrap the WAI pipeline in an exception-handling middleware that logs
  (and, once tracing exists, marks the span) before re-throwing, so an
  unhandled exception is no longer invisible to both the log and the
  trace.

**Do not adopt `prometheus-client` as a second, separate metrics path.**
OpenTelemetry's metrics API covers the same ground (request counters,
GHC RTS stats via `-T` once enabled) through the same SDK already being
added for traces, and running two instrumentation libraries side by
side for the same job is exactly the kind of complexity this proposal
is trying to avoid while the backend is still unpicked.

**Leave the two existing `fast-logger` log pipelines in place for now,**
reshaping field names toward GCP/Loki compatibility only once a
deployment target exists to actually test that against — doing it
speculatively, against neither, risks guessing wrong twice.

**Do not stand up a real Grafana instance or a GCP project as part of
this work.** That's specifically what's on the horizon rather than
decided; the recommendation above is deliberately the part that doesn't
need either to exist yet.

## 6. Decision

Decided: instrument now with OpenTelemetry, targeting a stdout exporter,
and fix the two logging gaps in the same pass. Revisit log-field
reshaping and pick a real OTLP destination once GCP/deployment-target
and Grafana-hosting decisions actually land — tracked as open work, not
blocking this decision.

Implementation (OpenTelemetry instrumentation plus the two logging-gap
fixes) is tracked in #273, per this repo's usual spike convention of not
building the change inside the spike itself.
