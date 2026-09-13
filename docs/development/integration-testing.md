# Integration Testing

A second, separate test suite exists for testing the application's
routes — the handlers that touch the database, reached the way a client
reaches them — against a real, disposable Postgres instance.
[`unit-testing.md`](unit-testing.md) covers why those handlers are
deliberately excluded from the unit suite; this is the answer that fills
that gap.

This doc covers how to run the suite and what it actually covers, as
currently built. For the full comparison of options and the reasoning
behind each choice below, see
[`../solution-proposals/integration-testing.md`](../solution-proposals/integration-testing.md)
(§11 has the final decision this doc restates as current fact) — this
doc only describes what landed, not the tradeoffs, and doesn't
re-litigate them.

## Where tests live, and how to run them

A separate cabal `test-suite integration` component, distinct from
`test-suite spec` — keeps the fast, DB-free unit suite fast, and makes
the (slower, Docker-dependent) integration suite an explicit, separate
target. Spec files live under `test-integration/`, mirroring the module
they cover, same convention as the unit suite's `test/`: e.g.
`Domain.Project.Responder.Api.Node.Post` is covered by
`test-integration/Domain/Project/Responder/Api/Node/PostSpec.hs`.
`Spec.hs` is the same one-line `hspec-discover` stub the unit suite
uses; `typeio.cabal`'s `test-suite integration` stanza still needs each
new spec module added to its `other-modules` by hand, same as `spec`.

Run it locally:

```
cabal test integration
# or:
make test-integration
```

**Needs Docker, nothing else** — no manually-started Postgres, and no
separately-installed `migrate` CLI (see "How migrations get applied"
below for why). It also runs in CI, on every PR into `main` and against
every merge-queue entry, via a separate
`.github/workflows/integration-test.yml` — and it is a **required**
check, alongside `test` (see [`ci.md`](ci.md) for the full picture).
Both must pass before a PR can merge. Local commands here still use the
scoped `integration` target rather than a bare `cabal test`, because
the latter would build and run *every* suite in the package, dragging
this suite's Docker dependency into runs that don't want it.

## Container lifecycle

`Integration.Support.withTestApp` starts one `postgres:15`
container (same version `local/script/start-postgres.sh` uses,
via [`testcontainers`](https://github.com/testcontainers/testcontainers-hs)/
`TestContainers.Hspec`), migrated and seeded with reference data before
any test runs, and torn down once the whole suite run finishes. Wired in
via Hspec's `aroundAll` (once per suite run), not `around` (once per
test) — one container, reused across every test in the run. It hands
each spec a `TestApp`: the `Application` built over that container, and
the pool underneath it.

### How migrations get applied

Not via the `migrate` CLI, and not from the Haskell test process at all.
`withTestApp` bind-mounts the real `migrations/` directory and
`test-integration/docker/apply-migrations.sh` into the official Postgres
image's `/docker-entrypoint-initdb.d/` — the image's own "run this once,
automatically, on first startup" convention. That script applies
`migrations/*.up.sql` with `psql` (already present in the image), in
filename order, skipping every `.down.sql`. Deliberately not the
`migrate` CLI: this way, running `cabal test integration` needs only
Docker, not a second tool installed on top of it. The container's
readiness check (`TC.waitForLogLine` **and** `TC.waitUntilMappedPortReachable`,
ANDed together) exists because Postgres logs "ready to accept
connections" once for an internal-only setup instance *before* the
init scripts run, then again after — checking the log line alone could
match too early, while the mapped port isn't actually listening until
the real, post-init restart.

## Test isolation: truncate between tests, not transaction rollback

`Integration.Support.resetBetweenTests` truncates every table a test
might have written to (`project.dependency`, `project.node`,
`project.project`, `RESTART IDENTITY CASCADE` — truncating all three
together sidesteps FK-ordering entirely) before each test, wired in via
Hspec's `beforeWith`. Not "wrap each test in a transaction and roll it
back": handlers call `runSqlPool` directly, which commits its own
transaction on completion, so there's no outer transaction for a test to
roll back without changing how the handler itself runs queries — see the
proposal's §5 for why that's out of scope. Reference data (see below) is
seeded once at container startup and untouched by this truncation.

## Seeding: two different things, kept separate

Two distinct mechanisms are in play here, and conflating them was an
actual mistake corrected once already on the solution-proposal doc
itself — worth getting right here too:

- **Reference data** — `NodeStatus`/`NodeType` lookup rows the app needs
  to function at all (`Domain.Central.Responder.Api.Seed.nodeStatuses`/
  `nodeTypes`). This is the **same** mechanism the running app uses to
  seed itself on startup — `Integration.Support` runs
  `Domain.Central.Responder.Api.Seed.seedReferenceData`, the very
  function the seed endpoint runs, once per container, not once per
  test. It is **not** demo or fixture data, and creates no
  `Project`/`Node` rows.
- **Test fixtures** — a `Project` and a root `Node` a write test needs
  to exist before it can do anything (e.g. `POST /api/project/nodes`
  needs a project to attach a new node to). Built by hand, per-test, via
  `Integration.Support.seedProjectWithRootNode` — plain `insert` calls,
  not routed through the app's seed mechanism. Centralized in
  `Integration.Support` since nearly every write test needs the same
  starting point, but it is fixture data for tests, not reference data
  for the app, and the two aren't merged into one mechanism.

## How a test reaches the code: by URL, through the real router

A spec builds no handler and calls no function under test. It asks
`Integration.Support` for the application and sends it a request:

```haskell
resp <- httpGet ta "/ui/project/stats?projectId=1"
statusOf resp `shouldBe` 200
bodyOf resp `shouldContainStr` "Total nodes"
```

`withTestApp` builds `App.Server.app` over the container's pool, so the
routing, the parameter parsing, the status codes and the content
negotiation in play are the application's own. A spec whose path or
parameter name is wrong fails, rather than passing against a function
nothing would route to. It also means a route's refusals are testable as
themselves: a missing or malformed parameter is a 400 from the router,
before any handler runs, and several specs pin exactly that.

What is *not* in the application under test is the middleware pipeline —
request-id tagging, logging, index rendering, static files. It is
composed around the application rather than inside it, and none of it is
what these tests are about.

`httpGet`/`httpPost`/`httpPut` take one URL string and split it with
`Network.HTTP.Types.URI.decodePath`, because the router matches on
`pathInfo` while every parameter is read off `queryString` — deriving
both from one string rules out a request that 404s for a reason
unrelated to what the test is asserting. Form bodies go through
`formBody`, which percent-encodes them the way a browser does.

### Three things that were evaluated and not adopted

- **`hspec-wai`.** It wraps exactly what `Integration.Support` now
  provides, but its `with` wants to own the spec's context, and
  `aroundAll withTestApp`/`beforeWith resetBetweenTests` already owns
  it — the container lifecycle is the harder half and `hspec-wai` does
  not help with it. The helpers it would have replaced are about
  twenty lines.
- **`servant-client`.** Clients derived from the API type would catch a
  drifting endpoint at compile time, but only across the five JSON
  routes; the UI routes answer HTML fragments, which is most of the
  suite. `App.Link`'s `safeLink` derivation covers the same drift for
  the application's own callers more cheaply.
- **A markup parser.** The assertions are substring matches, and a few
  had to be loosened when the status class joined `class="work"`. A
  parser would make them precise, but the weak assertions are weak in a
  way that fails loudly rather than passing wrongly, and the
  substring form keeps each spec readable as "this string is in the
  document". Worth revisiting if a loosened assertion ever misses a
  real regression.

## Shared helpers

Everything a spec needs comes from `Integration.Support`, rather than
being copy-pasted per file as the string helpers once were:

| Helper | For |
|---|---|
| `withTestApp` / `resetBetweenTests` | the container and the application over it, and truncation between tests |
| `seedProjectWithRootNode` / `seedWorkNode` / `seedDependency` | fixtures |
| `httpGet` / `httpPost` / `httpPut` / `formBody` | driving requests |
| `statusOf` / `bodyOf` / `headerOf` | reading responses |
| `shouldContainStr` / `shouldNotContainStr` / `countStr` / `indexOfStr` | asserting on markup |

## What's actually covered

Every route the application serves except `GET /healthz`,
`GET /api/system/config` and the read-only `GET` list endpoints, each
spec named for the route it drives:

- **`POST /api/project/nodes`** (the pilot —
  `Domain/Project/Responder/Api/Node/PostSpec.hs`) — chosen because it's
  a real, multi-table, foreign-key-and-join-driven write (`Project`,
  `NodeStatus`, `NodeType`, `Node`), the exact shape a unit test can't
  meaningfully exercise (see the proposal's §3). Covers the success path
  (a 201, a `Location` header, a new `Node` row and deliberately *no*
  `Dependency` edge) and the failure paths.
- **`POST /api/central/seed-database`** (`Domain/Central/Responder/Api/SeedSpec.hs`)
  — that the seed endpoint inserts every `NodeStatus`/`NodeType` the app
  defines, that it is idempotent, and — the boundary worth pinning —
  that it creates no projects or nodes of its own.
- **`POST /ui/create-project/submit`** (`.../ProjectCreate/SubmitSpec.hs`)
  — creates the `Project` and its `project_root` `Node`, and answers
  with the `HX-Location` header that moves the browser to the index.
  The failure path re-renders the form *without* that header, which is
  what tells the two 200s apart.
- **`GET`/`POST /ui/project/node/create`** (`.../ProjectManage/Node/CreateSpec.hs`)
  — the "Add work" panel. Covers the row it writes and the three things
  its response has to do at once: carry the new node's panel as an
  out-of-band swap, carry the `HX-Trigger` that makes the drawing
  refetch, and come back as the form again, with its complaint and
  nothing written, when the title is empty or only spaces.
- **`PUT /ui/project/node/{title,description,status}`** (`.../ProjectManage/Node/{Title,Description,Status}Spec.hs`)
  — each covers the column it replaces, a 422 carrying the field's own
  error markup (5xx would not be swapped into the page at all), and a
  404 for a node that isn't there.
- **`GET /ui/project/vw`** (`.../ProjectManage/ViewSpec.hs`) — the page
  shell's htmx wiring: attribute strings matching element ids defined
  elsewhere, which is exactly the pairing a compiler cannot check. Plus
  the canonical `data-view-base` the viewport appends to, and the 400s
  its `Strict` parameters produce.
- **The save-state indicator** (`.../ProjectManage/SaveStateSpec.hs`) —
  that the shell ships all three states and the script that switches
  between them, and that all three editable fields still declare
  themselves as saves. Whether they actually produce idle/saving/saved
  in order belongs to the browser, and lives in the E2E suite.
- **`GET /ui/project/stats`** (`.../ProjectManage/StatsSpec.hs`) — the
  arithmetic is covered as a pure function in `Domain.Project.StatsSpec`;
  what needs a real database is the pair of queries feeding it: the full
  status vocabulary, and counts restricted to the project's own work.
- **`GET /ui/project/graph`** — three specs. `Visualization/CommonSpec.hs`
  covers the `visualizationMode` switch itself: each drawing when asked
  for by name, the default when the parameter is absent, a known
  visualization in the wrong case (accepted — the vocabulary is matched
  case-insensitively), and a 400 for a value that names no
  visualization. `Visualization/Rootless/ResponderSpec.hs` and
  `Visualization/Orbital/ResponderSpec.hs` cover what each drawing is
  *of* — the conversion from rows to shapes, and for orbital the replica
  DOM contract that has no counterpart anywhere else.
