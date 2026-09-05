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
  // Single browser to start -- broaden only if a real cross-browser bug
  // surfaces.
  //
  // Two projects, not two browsers (#240). A server picks its
  // visualization once, at boot, from GRAPH_VISUALIZATION
  // (docs/architecture/visualization-switching.md), so one server cannot
  // serve both drawings -- and the orbital spec has nothing to run
  // against on a Layered one. The two projects differ only in which
  // server they point at.
  //
  // This is a consequence of the boot-time switch, not of the
  // visualization: #223 replaces it with a query parameter, and when it
  // lands these collapse back into one project against one server.
  projects: [
    {
      name: 'chromium',
      testIgnore: /orbital\.spec\.ts/,
      use: {
        ...devices['Desktop Chrome'],
        baseURL: process.env.E2E_BASE_URL ?? 'http://localhost:3000',
      },
    },
    {
      name: 'orbital',
      testMatch: /orbital\.spec\.ts/,
      use: {
        ...devices['Desktop Chrome'],
        baseURL:
          process.env.E2E_ORBITAL_BASE_URL ?? 'http://localhost:3001',
      },
    },
  ],
});
