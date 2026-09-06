# E2E Testing

A third, separate test suite exists on top of the unit
([`unit-testing.md`](unit-testing.md)) and integration
([`integration-testing.md`](integration-testing.md)) suites: a
[Playwright](https://playwright.dev/) suite that drives the app through a
real browser against a real running server and a real seeded Postgres —
not a Docker-managed disposable database like the integration suite's,
and not part of every PR's checks (see [CI wiring](#ci-wiring) below).

This doc covers where the suite lives, how to run it, what it covers,
and the Playwright/htmx interaction hazards found while writing it. For
the tool comparison and the reasoning behind choosing Playwright, see
[`../solution-proposals/e2e-testing.md`](../solution-proposals/e2e-testing.md)
(§6/§8 have the final decision this doc restates as current fact) — this
doc only describes what landed, not the tradeoffs.

## Where tests live, and how to run them

Specs live under `e2e/tests/`, a separate Node/npm project (its own
`package.json`, `playwright.config.ts`, `tsconfig.json`) rather than a
`cabal` test-suite component — this suite drives a browser via
Playwright's own Node.js API, not anything Haskell-side.

Unlike the unit and integration suites, this one doesn't start the app
itself — it drives a browser against whatever's already running at
`E2E_BASE_URL` (default `http://localhost:3000`). Start the app the same
way local development always does, from the repo root:

```
make start-app
```

— or the same steps by hand, one per terminal (see
[`onboarding.md`](onboarding.md) for more on either path):

```
make run-postgres      # start Postgres in Docker
make migrate-up        # apply all migrations
cabal run server        # start the app, reads .env
make seed-db           # seed reference data (NodeStatus/NodeType; needs the server already running)
```

Then, in a separate terminal, from the repo root:

```
make e2e-install   # first time only (npm install + Playwright's Chromium)
make test-e2e      # cd e2e && npm test
```

(Or, from `e2e/` directly: `npm install`,
`npx playwright install --with-deps chromium`, `npm test` — same thing,
what the `make` targets wrap.)

`make test-e2e`/`npm test` runs `playwright test` headless against every
spec in `e2e/tests/`. To point at a different host/port (e.g. a
non-default `WEB_PORT`):

```
E2E_BASE_URL=http://localhost:4000 npm test
```

### Watching it run

`make test-e2e`/`npm test` runs headless (no visible browser window) —
that's the default for a reason (faster, no display needed), but to
actually *watch* it drive a browser, run Playwright directly from `e2e/`
instead:

```
npx playwright test --headed              # opens a real browser window
npx playwright test --headed --slow-mo=500 # ...and pauses 500ms between actions, so you can actually follow along
npx playwright test --ui                   # Playwright's UI mode: a scrubbable timeline, live browser view, and DOM snapshot per step
```

`--ui` mode is the best way to actually see what a spec did after the
fact, action by action, not just pass/fail.

## What's actually covered

All four candidate workflows from the solution proposal's §7 are
covered:

- **`tests/create-project.spec.ts`** — the pilot: drives the add-project
  form end to end (navigate → open the form → fill it in → submit →
  assert the new project appears back on the project index). See that
  file's comments for why create-project was chosen as the pilot (it
  needs no pre-existing fixture data beyond the reference
  `NodeStatus`/`NodeType` rows `make seed-db` already provides) and the
  specific htmx-swap timing it's asserting around.
- **`tests/edit-node.spec.ts`** — adds a node (via a direct API call, not
  a UI interaction — the app has no UI affordance to create a node yet,
  see the spec's comments), then edits its title and description through
  the node-detail panel, asserting on each field's settled save-success
  indicator and on the re-fetched detail view afterward.
- **`tests/node-status.spec.ts`** — changes a node's status via the
  node-detail panel's status dropdown, asserting on the immediate
  save-success indicator and, separately, on the plain (non-edit) detail
  view's status text to confirm it actually persisted. See the spec's
  comments for a real app bug found while writing this (the edit
  dropdown never actually shows the node's real current status,
  regardless of what's in the database).
- **`tests/graph.spec.ts`** — the server-rendered dependency graph.
  Clicks a node and asserts its detail panel opens and it picks up the
  `.node-highlight` glow, then that closing clears both; that the boxes
  are laid out without overlapping; that no graph data is sent for a
  client to lay out (the d3 the viewport loads moves a transform, it
  does not compute positions); and that the viewport pans and zooms by
  keyboard, wheel and drag, since the viewport has no buttons to click. See
  the spec's
  comments for a severe app bug found while writing the first of these
  (the graph never positioned any node past the first one, long
  since fixed).
- **`tests/project-index-scroll.spec.ts`** — a bug fix's regression
  test, not one of the four candidate workflows above. Seeds
  enough projects to overflow the viewport and asserts the project
  index's last card is unreachable before a real wheel event and
  reachable after; separately, that the dependency graph page's `#view`
  stays `overflow: hidden` rather than picking up the scroll behaviour
  every other page now gets by default. See
  [`components.md`](ui/components.md) for the `#container`/`#view`
  design this fix settled on.
- **`tests/helpers.ts`** — shared setup (`createProject()`, `addNode()`,
  `createProjectFast()`) every spec above uses, so creating a
  project/node isn't duplicated across specs that need one but aren't
  testing its creation.

### What's not covered

- **No database reset between runs.** Unlike the integration suite
  (which truncates mutable tables before every test via
  `Integration.Support.resetBetweenTests`), nothing here resets the
  database — this suite drives the actual dev Postgres you started by
  hand (or CI's disposable one — see below). Specs give their fixture
  data timestamped titles so re-running locally doesn't collide with a
  previous run's rows, but the database will accumulate
  projects/nodes across runs until you reset it yourself (e.g.
  `make migrate-down-all && make migrate-up`).
- **Single browser (Chromium) for now** — broaden only if a real
  cross-browser bug surfaces.

## Playwright/htmx interaction hazards

These accumulated while writing the specs above, and every spec added
to this suite should follow the same conventions:

- **Locators and web-first assertions only, never fixed sleeps.** htmx's
  async partial swaps race a network-idle or sleep-based wait; a
  locator-based, auto-retrying assertion model doesn't need to know
  anything about the swap's timing.
- **`locator.fill()` doesn't reliably trigger htmx's `changed` trigger
  modifier.** Confirmed directly: a field wired to `hx-trigger="input
  changed delay:500ms"` (e.g. the node-edit panel's title/description
  fields) never fires its request after `.fill()`, no matter how long
  you wait — not a timing issue. Use `locator.selectText()` then
  `locator.pressSequentially()` instead for any field with a `changed`
  trigger; see `edit-node.spec.ts`'s comments for the full story
  (including why `fill('')` as a "clear first" step doesn't work
  either).
- **A freshly htmx-swapped-in element can need an explicit `click()`
  before Playwright's non-pointer interaction helpers (e.g.
  `selectOption()`) reliably trigger its own `hx-trigger`.** Confirmed on
  the node-edit panel's status `<select>`: calling `selectOption()`
  alone, right after the edit form swaps in, never fires its `change`
  PUT — but `locator.click()` immediately before it does, every time.
  Not a settle-timing issue (an artificial wait between the two doesn't
  fix it on its own) — see `node-status.spec.ts`'s comments. Reach for
  this if a spec's htmx request never fires despite the value/state
  visibly updating correctly client-side.
- **`locator.dispatchEvent('click')` for an element a real pointer
  genuinely can't reach.** `dispatchEvent('click')` fires the same event
  `hx-trigger="click"` reacts to without needing the element to be
  visually clickable first. Prefer a real `click()` whenever the element
  is actually reachable; reach for `dispatchEvent()` only when a known,
  separately-tracked rendering bug is what's in the way, not as a
  default habit.

  `dispatchEvent` is the workaround when an element cannot be reliably
  clicked at a screen position. `graph.spec.ts` does not need it: the
  server places nodes deterministically, so a real `click()` works and
  doubles as a check that nodes land somewhere visible. The technique
  stays documented because the situation recurs elsewhere.

## CI wiring

`.github/workflows/e2e-test.yml` runs this suite against a real,
compiled `server` process talking to a real, seeded Postgres, driven by
a headless browser. Unlike `test.yml`/`integration-test.yml`, it's
**informational only, not required, and deliberately not run on every
PR** — multi-process (browser + server + database), meaningfully slower
than the other suites, and a finding here isn't necessarily about what a
given PR changed. See [`ci.md`](ci.md)'s "E2E test workflow" section for
the step-by-step CI shape (starting Postgres via a plain `docker run`,
backgrounding `cabal run server`, seeding via
`POST /api/central/seed-database`, then `npm test`); this section covers
when it runs.

**Retries:** `playwright.config.ts` sets `retries: process.env.CI
? 2 : 0` — a transient timing flake in CI (htmx's debounce/indicator-box
timing, the kind `edit-node.spec.ts`'s own comments call out) gets a
couple of automatic reruns instead of failing the whole check outright.
Locally (`CI` unset) a failure gets zero retries, on purpose — it should
be investigated immediately, not silently retried away.

Three triggers, matched to three different needs:

- **`workflow_dispatch`** — run it right now, on demand, against any
  branch.
- **A weekly `schedule`** — catches drift: something breaking with no
  code change at all (a Playwright/browser update, an environment
  shift), same reasoning `security-scan.yml`'s own weekly run uses, on a
  different day so the two slow/occasional jobs don't contend for
  runners at once.
- **`pull_request`, gated on the `run-e2e` label** — either directly on
  the PR, or on any issue the PR closes:
  - **The PR's own `run-e2e` label** — the direct case: someone decides
    an already-open PR needs E2E coverage and labels it.
  - **Any issue the PR closes** (`Closes #N` etc. in the PR body —
    GitHub's own "closing issue references") **carrying `run-e2e`** —
    the planning-time case: label an issue `run-e2e` when it's
    created/triaged, as part of recording its requirements, before any
    PR exists for it. Whichever PR later closes that issue picks the
    requirement up automatically, via a GraphQL query
    (`closingIssuesReferences`) the workflow's `check-e2e-required` job
    makes — a linked issue's labels aren't part of the `pull_request`
    event payload, so this can't be a plain `if:` expression the way the
    PR's own label check is.

  Either path sets `required=true`; the real `e2e-test` job `needs:`
  `check-e2e-required` and gates on that output. An unlabeled PR with no
  qualifying linked issue costs one cheap job that reports quickly — the
  two-job split keeps that fast precondition check separate from ever
  having to spin up (or skip inside) the full GHC+Docker+Postgres+browser
  job. See `CLAUDE.md`'s Ticket & Branching Conventions for when to apply
  `run-e2e` at issue-creation time.

## Setup/config it needs

- **Node.js** (any version current enough to run Playwright; this suite
  was built against Node 20) — the only prerequisite beyond what
  [`onboarding.md`](onboarding.md) already requires to run the app
  locally (GHC/cabal, Docker, a `.env` at the repo root).
- **`E2E_BASE_URL`** — the only suite-specific env var, defaulting to
  `http://localhost:3000`; override it to point at a non-default host or
  port (e.g. a non-default `WEB_PORT`).
- No suite-specific `.env` entries — CI sets the same shape of vars
  `.env` sets locally directly as job env vars (no `.env` file on the
  runner); `Config.App`/`Config.Db`/`Config.Web` read them the same way
  either way.
