# Integration Testing

A second, separate test suite exists for testing responders — WAI
handlers that touch the database directly — against a real, disposable
Postgres instance. [`unit-testing.md`](unit-testing.md) covers why
responders are deliberately excluded from the unit suite; this is the
answer that fills that gap.

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
below for why). It also runs in CI, on every PR into `main` that
touches Haskell-relevant files, via a separate
`.github/workflows/integration-test.yml` — but informational only, not
yet a required check (see [`ci.md`](ci.md) for the full rationale).
`cabal test spec`/`make test` is the one CI *requires*, which is exactly
why local commands here use the scoped `integration` target rather than
a bare `cabal test` — the latter would build and run this suite too.

## Container lifecycle

`Integration.Support.withTestDatabase` starts one `postgres:15`
container (same version `local/script/start-postgres.sh` uses,
via [`testcontainers`](https://github.com/testcontainers/testcontainers-hs)/
`TestContainers.Hspec`), migrated and seeded with reference data before
any test runs, and torn down once the whole suite run finishes. Wired in
via Hspec's `aroundAll` (once per suite run), not `around` (once per
test) — one container, reused across every test in the run.

### How migrations get applied

Not via the `migrate` CLI, and not from the Haskell test process at all.
`withTestDatabase` bind-mounts the real `migrations/` directory and
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
back": responders call `runSqlPool` directly, which commits its own
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
  seed itself on startup — reused directly (`insertUnique` over each
  list) by `Integration.Support.seedReferenceData`, once per container,
  not once per test. It is **not** demo or fixture data, and creates no
  `Project`/`Node` rows.
- **Test fixtures** — a `Project` and a root `Node` a write-responder
  test needs to exist before it can do anything (e.g. `handlePostNode`
  needs a project and a root node to attach a new node's `Dependency`
  edge to). Built by hand, per-test, via
  `Integration.Support.seedProjectWithRootNode` — plain `insert` calls,
  not routed through the app's seed mechanism. Centralized in
  `Integration.Support` since every mutating-responder integration test
  (this pilot and its follow-ups) needs the same starting
  point, but it is fixture data for tests, not reference data for the
  app, and the two aren't merged into one mechanism.

## What's actually covered

All five write/mutate handlers now have integration coverage: the pilot
plus four follow-ups, each asserting against actual
inserted/updated rows after driving the handler through
`Network.Wai.Test.runSession`/`srequest`, form-encoded the same way a
real client would submit it.

- **`Domain.Project.Responder.Api.Node.Post.handlePostNode`** (the
  pilot —
  `test-integration/Domain/Project/Responder/Api/Node/PostSpec.hs`) —
  chosen because it's a real, multi-table, foreign-key-and-join-driven
  write (`Project`, `NodeStatus`, `NodeType`, `Node`, `Dependency`), the
  exact shape a unit test can't meaningfully exercise (see the
  proposal's §3). Covers the success path (a new `Node` row plus its
  `Dependency` edge to the root) and a failure path (404 for a
  nonexistent project).
- **`Domain.Project.Responder.Ui.ProjectManage.Node.Description.handlePutDescription`**
  (
  `test-integration/Domain/Project/Responder/Ui/ProjectManage/Node/DescriptionSpec.hs`)
  — seeds a project/root node via `seedProjectWithRootNode`, then covers
  the success path (the `Node`'s `description` column is replaced) and a
  failure path (500 for a nonexistent node).
- **`Domain.Project.Responder.Ui.ProjectManage.Node.Status.handlePutNodeStatus`**
  (
  `test-integration/Domain/Project/Responder/Ui/ProjectManage/Node/StatusSpec.hs`)
  — same seeding, covers the success path (the `Node`'s
  `NodeStatus` foreign key is updated to the seeded `closed` status) and
  a failure path (404 for a nonexistent node).
- **`Domain.Project.Responder.Ui.ProjectManage.Node.Title.handlePutTitle`**
  (
  `test-integration/Domain/Project/Responder/Ui/ProjectManage/Node/TitleSpec.hs`)
  — same seeding, covers the success path (the `Node`'s `title` column
  is replaced) and a failure path (404 for a nonexistent node).
- **`Domain.Project.Responder.Ui.ProjectCreate.Submit.handleProjectSubmit`**
  (
  `test-integration/Domain/Project/Responder/Ui/ProjectCreate/SubmitSpec.hs`)
  — unlike the others, this handler *creates* the `Project`/root `Node`
  rather than mutating an existing one, so it needs no
  `seedProjectWithRootNode` fixture, only the reference data
  `withTestDatabase` already seeds. Covers the success path (a new
  `Project` and a `project_root` `Node` with the submitted title/
  description) and a failure path (an invalid payload creates no
  `Project` at all).
