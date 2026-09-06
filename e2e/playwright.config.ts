import { defineConfig, devices } from '@playwright/test';

// Playwright infrastructure for typeio's E2E suite -- see
// docs/solution-proposals/e2e-testing.md (#17) for the design rationale,
// e2e/README.md for how to run this locally.
//
// Deliberately does NOT start the app itself (no `webServer` entry):
// this suite drives a real running server + real seeded Postgres,
// started manually the same way local development already does
// (`make run-postgres`, `make migrate-up`, `make seed-db`,
// `cabal run server`) -- see README.md for the exact sequence.
//
// CI-wired since #98 (.github/workflows/e2e-test.yml runs this suite for
// real on run-e2e-labeled PRs, the weekly schedule, and workflow_dispatch).
// `retries` is the one CI-specific knob set here so far (#152) -- a
// transient timing flake (htmx's debounce/indicator-box timing, the exact
// kind edit-node.spec.ts's own comments call out) gets a couple of
// automatic reruns in CI instead of failing the whole check outright; 0
// retries locally, where a failure should be investigated immediately
// rather than silently retried. Trace/video capture is still left at
// Playwright's defaults (off) until real CI runtime/artifact-storage cost
// is known.
export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  use: {
    baseURL: process.env.E2E_BASE_URL ?? 'http://localhost:3000',
  },
  // Single browser to start -- broaden only if a real cross-browser bug
  // surfaces.
  //
  // Back to one project as of #223. #240 briefly needed two, against two
  // servers on different ports: a server used to pick its visualization
  // once at boot from GRAPH_VISUALIZATION, so one process could not
  // serve both drawings and orbital.spec.ts had nothing to run against
  // on a Layered one. The choice is a `visualizationMode` query
  // parameter now, so every spec drives the same server and says in its
  // own URLs which drawing it wants.
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
