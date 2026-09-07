import { test, expect } from '@playwright/test';
import { createProject } from './helpers';

// Pilot spec for typeio's E2E suite. Create-project is the first
// workflow covered because it needs no pre-existing fixture data beyond
// the reference NodeStatus/NodeType rows `make seed-db` already
// provides, and every other candidate workflow depends on a project
// existing -- see docs/development/e2e-testing.md. Follow-up
// workflows (add/edit a node, change status, the dependency graph) are
// workflows live in their own specs.
//
// Convention for every spec in this suite: locators and web-first
// (auto-retrying) assertions for every htmx-swapped region, never a
// fixed sleep, and assert only on the settled end state -- never
// mid-transition (relevant for hyperscript flash effects elsewhere in
// the app, though this particular workflow doesn't use one).
//
// This drives the create-project form directly rather than just calling
// helpers.createProject() (which itself drives the same form) -- this
// spec IS the test of that flow; other specs call the helper because
// creating a project is only their setup, not what they're testing.
test('creating a project shows it on the project index', async ({ page }) => {
  // Unique per run so this is safe to re-run locally against a
  // long-lived dev database without colliding with a previous run's
  // row -- see README.md's "Notes" for why nothing resets the database
  // between local runs (unlike the integration suite's per-test
  // truncation).
  const title = `E2E create-project ${Date.now()}`;
  const description = `Created by e2e/tests/create-project.spec.ts at ${new Date().toISOString()}`;

  // Direct navigation (not an htmx request), so
  // Domain.Central.Middleware.IndexRender wraps the response in the
  // full page shell, which itself htmx-`load`s this same path to fetch
  // the actual view -- see docs/development/ui/index.md for the
  // #container/#view pattern this relies on.
  await page.goto('/ui/projects/vw');

  await page.getByRole('button', { name: 'Create Project' }).click();

  // getByLabel() -- each control here carries an `id` matching its
  // <label for="...">, which is the association getByLabel depends on.
  await page.getByLabel('Title:').fill(title);
  await page.getByLabel('Description:').fill(description);
  await page.getByRole('button', { name: 'Submit' }).click();

  // A successful submit responds with an `Hx-Location` header pointing
  // back at /ui/projects/vw (Submit.redirectHeader), which htmx follows
  // and swaps into #container; that view then itself htmx-`load`s the
  // project list fragment. Asserting on the settled result here (the
  // new project's rendered card) rather than any intermediate state
  // covers both hops without needing to know about either explicitly.
  // .project-item, not #project-index: see helpers.ts's createProject()
  // for why (#project-index is the single list container, not a
  // per-card element -- filter() needs the latter to actually narrow).
  const card = page.locator('.project-item').filter({ hasText: title });
  await expect(card.getByRole('heading', { name: title, level: 3 })).toBeVisible();
  await expect(card.getByText(description)).toBeVisible();
});

test('createProject() helper produces a usable project id', async ({ page }) => {
  // A light check on the shared helper itself (used as setup by other
  // specs, e.g. edit-node.spec.ts) -- not re-testing the form (the test
  // above already does that in full), just that the id it scrapes back
  // is a real, non-empty numeric string.
  const project = await createProject(page, 'E2E helper-check project');
  expect(project.id).toMatch(/^\d+$/);
});
