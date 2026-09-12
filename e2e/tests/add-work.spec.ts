import { test, expect } from '@playwright/test';
import { createProject } from './helpers';

// Creating a node from the Manage Project view.
//
// This is the app's only way to add work without a direct API call --
// every other spec in this suite reaches for helpers.ts's addNode() for
// exactly that reason -- and it spans three things that only agree in a
// browser: the panel that submits closes itself, the new node's own
// panel opens out of band, and the server-rendered drawing is refetched
// so the node is actually in it.
//
// Rootless is asked for by name, the same way the other layout specs do
// it: the default visualization moves, and this needs one shape per
// node to count.
const manageUrl = (projectId: string) =>
  `/ui/project/vw?projectId=${projectId}&visualizationMode=Rootless`;

test('adding work creates the node, draws it, and opens its panel', async ({ page }) => {
  const project = await createProject(page, 'E2E add work');
  const title = `Wire the thing ${Date.now()}`;

  await page.goto(manageUrl(project.id));
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute('transform', /translate/, {
    timeout: 10_000,
  });

  // Rootless draws the project's work and nothing else, so a project
  // with no work yet draws nothing at all.
  await expect(page.locator('#graph-nodes .node')).toHaveCount(0);

  // Closed is empty: the panel holds no corner of the canvas until it
  // is opened.
  await expect(page.locator('#add-work-panel')).toBeEmpty();

  await page.getByRole('button', { name: 'Add work' }).click();
  await expect(page.locator('#add-work-form')).toBeVisible();

  await page.getByLabel('Title').fill(title);
  await page.getByRole('button', { name: 'Create' }).click();

  // The node panel opens on the node that was just made -- an out-of-
  // band swap, since the form's own target is the panel it lives in.
  await expect(page.locator('#node-detail header h2')).toHaveText(title, {
    timeout: 10_000,
  });

  // ...the creation panel closes itself, by being emptied.
  await expect(page.locator('#add-work-panel')).toBeEmpty();

  // ...and the drawing has the node in it. This is the half that needs
  // the response's HX-Trigger: the graph is rendered server-side, so
  // without a refetch the new node exists everywhere except on screen.
  await expect(page.locator('#graph-nodes .node')).toHaveCount(1);
  await expect(page.locator('#graph-nodes .node text').first()).toContainText('Wire');
});

test('adding work with no title says so and creates nothing', async ({ page }) => {
  const project = await createProject(page, 'E2E add work empty');

  await page.goto(manageUrl(project.id));
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute('transform', /translate/, {
    timeout: 10_000,
  });

  await page.getByRole('button', { name: 'Add work' }).click();
  await page.getByRole('button', { name: 'Create' }).click();

  // The form comes back with its complaint rather than an error page:
  // it is its own target, so what returns is what the person is left
  // looking at, with the panel still open.
  await expect(page.locator('#add-work-panel .error-message')).toHaveText(
    'Title cannot be empty'
  );
  await expect(page.locator('#add-work-form')).toBeVisible();

  // Nothing was drawn, and no node panel opened.
  await expect(page.locator('#graph-nodes .node')).toHaveCount(0);
  await expect(page.locator('#node-panel')).toBeEmpty();
});

test('the creation panel can be closed without creating anything', async ({ page }) => {
  const project = await createProject(page, 'E2E add work close');

  await page.goto(manageUrl(project.id));
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute('transform', /translate/, {
    timeout: 10_000,
  });

  await page.getByRole('button', { name: 'Add work' }).click();
  await expect(page.locator('#add-work-form')).toBeVisible();

  await page.getByRole('button', { name: 'Close add work' }).click();
  await expect(page.locator('#add-work-panel')).toBeEmpty();
  await expect(page.locator('#graph-nodes .node')).toHaveCount(0);
});
