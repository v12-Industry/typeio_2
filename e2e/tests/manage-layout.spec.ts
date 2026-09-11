import { test, expect } from '@playwright/test';
import { addNode, createProject } from './helpers';

// The Manage Project view's layout: the graph owns the whole canvas,
// and the node detail panel floats over it rather than taking a column
// beside it.
//
// This is asserted in a browser because it is entirely a CSS result --
// nothing about it is visible in the markup the server sends, and the
// heights involved only resolve once a real viewport exists. A unit or
// integration test would pass on a page that rendered as a blank strip.

const box = async (page: import('@playwright/test').Page, selector: string) => {
  const b = await page.locator(selector).boundingBox();
  if (!b) throw new Error(`${selector} has no box`);
  return b;
};

test('the graph canvas fills the view', async ({ page, request }) => {
  const project = await createProject(page, 'E2E manage-layout');
  await addNode(request, project.id, 'E2E layout node');

  await page.goto(`/ui/project/vw?projectId=${project.id}`);
  await expect(page.locator('#graph-nodes .node, #graph-nodes .disc').first()).toBeAttached();

  const view = await box(page, '#view');
  const canvas = await box(page, '#tree-container');

  // The whole width, not a fraction of it -- the panel used to take a
  // column out of this.
  expect(canvas.width).toBeCloseTo(view.width, 0);
  expect(canvas.height).toBeCloseTo(view.height, 0);

  // And the view itself is a real region, not a strip collapsed to
  // whatever the drawing happened to be: #view's height is an explicit
  // subtraction from the viewport, so it has to be most of it.
  const viewport = page.viewportSize();
  if (!viewport) throw new Error('no viewport size');
  expect(view.height).toBeGreaterThan(viewport.height * 0.6);

  // ...and no taller than the room it actually has. #view's height is
  // a subtraction naming every band above it, and #view clips rather
  // than scrolls, so a band left out of that sum doesn't show up as a
  // scrollbar -- the bottom of the canvas just falls past the fold and
  // becomes unreachable. Pinning the bottom edge is what catches it.
  expect(view.y + view.height).toBeLessThanOrEqual(viewport.height);
});

test('the closed node panel does not sit over the canvas', async ({ page, request }) => {
  const project = await createProject(page, 'E2E manage-layout closed');
  await addNode(request, project.id, 'E2E layout closed node');

  await page.goto(`/ui/project/vw?projectId=${project.id}`);
  await expect(page.locator('#graph-nodes .node, #graph-nodes .disc').first()).toBeAttached();

  // Empty is the panel's closed state -- htmx swaps its innerHTML in
  // and out. An empty overlay left in place would still hold its corner
  // of the canvas and swallow drags meant for the graph, so it takes no
  // box at all.
  await expect(page.locator('#node-panel')).toBeEmpty();
  await expect(page.locator('#node-panel')).not.toBeVisible();
});

test('the open node panel floats over the graph rather than displacing it', async ({
  page,
  request,
}) => {
  const project = await createProject(page, 'E2E manage-layout panel');
  const node = await addNode(request, project.id, 'E2E layout panel node');

  await page.goto(`/ui/project/vw?projectId=${project.id}`);
  await expect(page.locator('#graph-nodes .node, #graph-nodes .disc').first()).toBeAttached();
  const before = await box(page, '#tree-container');

  // Deep-link the panel open, the same shape the graph's own click
  // pushes into the address bar.
  await page.goto(`/ui/project/vw?projectId=${project.id}&nodeId=${node.id}`);
  await expect(page.locator('#node-detail header h2')).toHaveText(node.title);

  const after = await box(page, '#tree-container');
  const panel = await box(page, '#node-panel');

  // The canvas is exactly the size it was: the panel took none of it.
  expect(after.width).toBeCloseTo(before.width, 0);
  expect(after.height).toBeCloseTo(before.height, 0);

  // ...and the panel is genuinely on top of it, not tucked beside it.
  const overlaps =
    panel.x < after.x + after.width &&
    after.x < panel.x + panel.width &&
    panel.y < after.y + after.height &&
    after.y < panel.y + panel.height;
  expect(overlaps, 'the panel overlaps the canvas').toBe(true);

  // Inset from the canvas edge rather than flush against it, which is
  // what makes it read as a window over the drawing.
  expect(panel.x).toBeGreaterThan(after.x);
  expect(panel.x + panel.width).toBeLessThan(after.x + after.width + 1);
});
