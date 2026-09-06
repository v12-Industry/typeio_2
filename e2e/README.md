# E2E Tests

A [Playwright](https://playwright.dev/) suite that drives the app
through a real browser against a real running server and real seeded
Postgres — not a Docker-managed disposable database like
`test-integration/`. See
[`docs/development/e2e-testing.md`](../docs/development/e2e-testing.md)
for the full write-up (what's covered, the Playwright/htmx interaction
hazards found so far, and how CI wires this suite in via the `run-e2e`
label) and `docs/solution-proposals/e2e-testing.md` (#17) for the
original design rationale; this file is just the quick-start pointer for
running what's here right now.

## Prerequisites

- Everything [`docs/development/onboarding.md`](../docs/development/onboarding.md)
  already requires to run the app locally (GHC/cabal, Docker, a `.env`
  at the repo root).
- Node.js (any version current enough to run Playwright; this suite was
  built against Node 20).

## Running it locally

This suite doesn't start the app itself — it drives a browser against
whatever's already running at `E2E_BASE_URL` (default
`http://localhost:3000`). Start the app the same way local development
always does, from the repo root — the one-command path:

```
make start-app
```

— or the same steps by hand, one per terminal:

```
make run-postgres      # start Postgres in Docker
make migrate-up        # apply all migrations
cabal run server        # start the app, reads .env
make seed-db           # seed reference data (NodeStatus/NodeType; needs the server already running)
```

See [`onboarding.md`](../docs/development/onboarding.md) for more on
either path. Then, in a separate terminal, from the repo root:

```
make e2e-install   # first time only (npm install + Playwright's Chromium)
make test-e2e      # cd e2e && npm test
```

(Or, from this directory directly: `npm install`,
`npx playwright install --with-deps chromium`, `npm test` — same thing,
what the `make` targets wrap.)

`npm test`/`make test-e2e` runs `playwright test` headless against every
spec in `tests/`. To point at a different host/port (e.g. a non-default
`WEB_PORT`):

```
E2E_BASE_URL=http://localhost:4000 npm test
```

### Specs that need a particular visualization

One server serves all of them. A spec that needs a specific drawing puts
`visualizationMode` on the page URL — `orbital.spec.ts` navigates to
`/ui/project/vw?projectId=…&visualizationMode=Orbital`, and the page
forwards it to the htmx request that fetches the graph fragment.

A spec that names none gets `Config.Visualization`'s hardcoded default,
which is whichever visualization was added most recently. Worth knowing
when reading `graph.spec.ts`: it asks for `Layered` explicitly rather
than relying on that default, precisely so it keeps testing the layered
drawing when a newer one arrives.

Between #240 and #223 this needed a second server on its own port,
because the visualization came from `GRAPH_VISUALIZATION` at boot. That
is gone along with the variable — see
[`visualization-switching.md`](../docs/architecture/visualization-switching.md).

### Watching it run

`make test-e2e`/`npm test` runs headless (no visible browser window) —
that's the default for a reason (faster, no display needed), but to
actually *watch* it drive a browser, run Playwright directly from this
directory instead:

```
npx playwright test --headed              # opens a real browser window
npx playwright test --headed --slow-mo=500 # ...and pauses 500ms between actions, so you can actually follow along
npx playwright test --ui                   # Playwright's UI mode: a scrubbable timeline, live browser view, and DOM snapshot per step
```

`--ui` mode is the best way to actually see what a spec did after the
fact, action by action, not just pass/fail.

## What's covered

- `tests/create-project.spec.ts` — the pilot: drives the add-project
  form end to end.
- `tests/edit-node.spec.ts` — adds a node, then edits its title and
  description through the node-detail panel.
- `tests/node-status.spec.ts` — changes a node's status via the
  node-detail panel's status dropdown.
- `tests/graph.spec.ts` — clicks a node in the D3-rendered dependency
  graph and asserts its detail panel opens/highlights/clears correctly.
- `tests/project-index-scroll.spec.ts` — a project index with more rows
  than fit on screen can be scrolled to the last one (#210), and the
  graph page's own viewport doesn't gain a competing scrollbar.
- `tests/helpers.ts` — shared setup (`createProject()`, `addNode()`,
  `createProjectFast()`) every spec above uses.

All four candidate workflows from the proposal's §7 are covered, and CI
wiring landed in #98; `project-index-scroll.spec.ts` is later, separate
coverage for a bug fix rather than one of those four. See
[`docs/development/e2e-testing.md`](../docs/development/e2e-testing.md)
for the full breakdown of each spec, what's deliberately not covered,
and the app bugs found while writing them (#120 among others) — this
file stays a plain "how to run it" pointer rather than duplicating that.

## Notes

The Playwright/htmx interaction hazards accumulated while writing this
suite (fixed-sleep avoidance, `locator.fill()` not triggering htmx's
`changed` modifier, needing an explicit `click()` before some
non-pointer interactions, `dispatchEvent('click')` for unreachable
elements) are documented in
[`docs/development/e2e-testing.md`](../docs/development/e2e-testing.md)
rather than here, so they live in one place — see each spec's own
comments for the specific case that motivated it.
