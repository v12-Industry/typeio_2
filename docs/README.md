# docs

Repository for architecture notes, developer documentation, and solution
proposals for this project.

## Layout

- `solution-proposals/` — spike/investigation write-ups that compare options
  for a problem and recommend a path forward, before implementation work is
  ticketed. One document per proposal, named for its topic. These are a
  point-in-time decision record, not a live source of truth: a proposal's
  own confident "Decision" section is not proof the decision was actually
  implemented, or still holds. Always check the doc's `Status` line, and
  cross-check `development/` for whether it actually happened, before
  treating a proposal as current guidance.
- `development/` — reference docs on how the app *actually, currently*
  works, grouped by area (`ui/`, `frontend/`, `backend/`,
  `visualizations/`), plus onboarding. Each area has an `index.md`
  linking its own files, except `backend/`, whose files are listed
  individually in the index below. This is the primary
  reference for development decisions — if something isn't reflected here,
  it either isn't built yet or isn't true.
- `architecture/` — how a part of the system is *designed*: module
  structure, the contracts between components, and the invariants a change
  there must respect. Unlike `development/`, a doc here may describe a
  design that is only partly built — as long as it says so and shows which
  parts exist — which is what gives multi-issue work a stable reference
  while it's in flight. See [`architecture/README.md`](architecture/README.md)
  for the full distinction.

## Index

- [`development/onboarding.md`](development/onboarding.md) — **start here.** Setup steps and a request-lifecycle walkthrough linking everything else below.
- [`development/ui/index.md`](development/ui/index.md) — the `#container`/`#view` component pattern, how UI is rendered directly in Haskell (Lucid), the global-vs-scoped CSS split, and the color-token/indicator/loading-state design system.
- [`development/frontend/index.md`](development/frontend/index.md) — HTMX and hyperscript: the attribute-driven client-side interactivity, with concrete patterns from the codebase.
- [`development/visualizations/index.md`](development/visualizations/index.md) — what each graph visualization actually draws, one doc per visualization ([Layered](development/visualizations/layered.md), [Rootless](development/visualizations/rootless.md), [Orbital](development/visualizations/orbital.md)); the switching mechanism itself is [`architecture/visualization-switching.md`](architecture/visualization-switching.md).
- [`development/backend/routing.md`](development/backend/routing.md) — the `Data.HashTree`-based router: how routes are built, and the prefix-match/per-request-rebuild behavior worth knowing about.
- [`development/backend/environment.md`](development/backend/environment.md) — the `Env` record (config, logger, DB pool) acquired once at startup, and how it differs from Containers.
- [`development/backend/containers.md`](development/backend/containers.md) — the Container dependency-injection pattern: Root → per-domain → API/UI sub-containers.
- [`development/backend/logging.md`](development/backend/logging.md) — the two independent structured-JSON logging pipelines (request/response, and database queries) and why they're separate.
- [`development/backend/database-schema.md`](development/backend/database-schema.md) — the `project` schema's six tables and one view, what each represents, how they relate, and a mermaid ER diagram — grounded in `migrations/000001`–`000008` and `Domain.Project.Model`.
- [`development/ci.md`](development/ci.md) — the six GitHub Actions workflows: which one is required to merge, which are informational, `main`'s merge queue and how to add a PR to it, and how to reproduce each check locally.
- [`development/dependency-security.md`](development/dependency-security.md) — the full Dependabot + security-scanning picture: what each of the two mechanisms (native Dependabot/secret scanning vs. the OSV-Scanner CI workflow) covers, where their findings surface, and how to triage what comes up.
- [`development/unit-testing.md`](development/unit-testing.md) — where tests live, how to run them, what's actually covered (and what's deliberately not, and why).
- [`development/integration-testing.md`](development/integration-testing.md) — the responder-testing suite unit tests deliberately skip: a disposable `testcontainers` Postgres, truncate-based isolation, the reference-data-vs-fixture seeding split, and what's covered — every write/mutate handler, plus all three visualizations' rendered markup.
- [`development/e2e-testing.md`](development/e2e-testing.md) — the Playwright suite that drives the app through a real browser against a real running server and seeded Postgres: where specs live, how to run them (headless or headed/UI mode), what's covered, the Playwright/htmx interaction hazards found so far, and how the `run-e2e`-label-gated CI job is wired up.
- [`development/labels.md`](development/labels.md) — the GitHub issue label taxonomy and when to use each: `type:*`, `area:*`, and the `viz:*` dimension saying which visualization an issue is for; plus the special-purpose labels outside the taxonomy (`run-e2e`, and the two merge-authorization labels `review:approved` and `review:pre-approve`).
- [`development/release-management.md`](development/release-management.md) — how to cut a release (bump `typeio.cabal`'s `version:`), what happens automatically once it merges (tag + GitHub Release), and what deliberately doesn't exist yet (`CHANGELOG.md`, Milestones, release branches).
- [`development/infrastructure.md`](development/infrastructure.md) — repo-level config (GitHub branch protection) managed as OpenTofu + Terragrunt, the Google Cloud Storage state backend, and how to import/plan/apply it — including what one-time account setup it still needs before it can run at all.
- [`architecture/README.md`](architecture/README.md) — what belongs in `architecture/` versus `development/` versus `solution-proposals/`, and why the directory exists.
- [`architecture/graph-rendering.md`](architecture/graph-rendering.md) — the *layered* layout engine's pipeline and rendering, shared by the Layered and Rootless visualizations: module map, per-phase contracts and invariants, coordinate and edge-direction conventions, the DOM contract, viewport behaviour and testing.
- [`architecture/visualization-switching.md`](architecture/visualization-switching.md) — how the app holds several visualizations of the dependency graph and picks one per request: the `visualizationMode` request parameter, the container seam it dispatches through, and the isolation rule governing what visualizations may and may not share. The doc a new visualization has to be read against.
- [`architecture/orbital-dependency-weighted-graph.md`](architecture/orbital-dependency-weighted-graph.md) — the orbital dependency-weighted visualization: the DAG unfolded into a forest of radial trees, one per head, with shared dependencies replicated per work stream so the drawing has no crossing edges at all. Covers the unfolding and radial-placement contracts, per-node colour identity, the replica DOM contract, and where the per-visualization seam sits. What it draws day to day is [`development/visualizations/orbital.md`](development/visualizations/orbital.md).
- [`solution-proposals/haskell-auto-formatting.md`](solution-proposals/haskell-auto-formatting.md) — **decided**: an auto-formatting setup for `.hs` files that works for both human editors (format-on-save) and AI agents, resolved as Fourmolu with the manual `=`/import-column alignment convention retired.
- [`solution-proposals/unit-testing.md`](solution-proposals/unit-testing.md) — which test framework to use, which modules are worth testing, and a mocking strategy for the Container-based responder modules.
- [`solution-proposals/e2e-testing.md`](solution-proposals/e2e-testing.md) — **decided**: browser-driven E2E tooling for the htmx/hyperscript/D3 UI, resolved as Playwright with an on-demand/scheduled CI job (seeded Postgres, running server, headless browser).
- [`solution-proposals/integration-testing.md`](solution-proposals/integration-testing.md) — **decided**: the deferred responder-testing question from the unit-testing decision, resolved as a disposable Postgres via `testcontainers`, truncate-based test isolation, and a pilot flow.
- [`solution-proposals/lazy-request-transactions.md`](solution-proposals/lazy-request-transactions.md) — **decided against**: explored lifting the transaction boundary for cross-domain atomicity, kept as a record of why that turned out to be unnecessary.
- [`solution-proposals/security-scanning.md`](solution-proposals/security-scanning.md) — **decided**: dependency/vulnerability scanning for CI, resolved as native Dependabot + secret scanning (free, public repo) plus OSV-Scanner as the Hackage gap-filler Dependabot doesn't cover yet, plus removing `wifi-password` (`package.json`), an orphaned, unshipped dependency.
- [`solution-proposals/release-management.md`](solution-proposals/release-management.md) — **decided**: versioning, tagging, and GitHub Releases for a pre-1.0, single-maintainer project, resolved as semver bumps triggering an automated tag+release, no `CHANGELOG.md` or Milestones, no release branches yet.
- [`solution-proposals/haskell-graph-rendering.md`](solution-proposals/haskell-graph-rendering.md) — **decided**: replacing D3 with a layered (Sugiyama-style) graph-drawing pipeline computed in pure Haskell and rendered as server-side SVG, including the layout requirements derived from its reference images, with the live reference in `architecture/graph-rendering.md`.
- [`solution-proposals/ci-cache-warming.md`](solution-proposals/ci-cache-warming.md) — **decided**: why every PR's first push and every merge-queue entry cold-builds despite an identical cache existing elsewhere (GitHub Actions cache scope, not a key mismatch — confirmed with real run data), resolved as a push-to-`main`, build-only workflow to warm the cache.
