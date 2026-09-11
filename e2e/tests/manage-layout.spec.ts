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

// The panel is anchored to the node it describes, which is a shape
// inside a pannable SVG -- so where it lands is measured in the browser
// and cannot be seen in the markup the server sends. Rootless is pinned
// for the same reason graph-viewport.spec.ts pins it: the default
// visualization moves, and this needs one node shape per node.
test('the open node panel is anchored under its node', async ({ page, request }) => {
  const project = await createProject(page, 'E2E anchor');
  const node = await addNode(request, project.id, 'E2E anchor node');

  await page.goto(
    `/ui/project/vw?projectId=${project.id}&nodeId=${node.id}&visualizationMode=Rootless`
  );
  await expect(page.locator('#node-detail header h2')).toHaveText(node.title);
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute('transform', /translate/, {
    timeout: 10_000,
  });

  const shape = await box(page, `#graph-nodes [data-node-id="${node.id}"]`);
  // Polled: the placement runs off a requestAnimationFrame, so the
  // first paint after the swap can still be at the fallback corner.
  await expect
    .poll(async () => {
      const panel = await box(page, '#node-panel');
      return panel.y > shape.y + shape.height;
    })
    .toBe(true);

  const panel = await box(page, '#node-panel');

  // Centred on the node horizontally. The tolerance is for the clamp
  // that keeps the panel on the canvas, which does not bite here --
  // this node opens in the middle of a wide canvas.
  const panelCentre = panel.x + panel.width / 2;
  const shapeCentre = shape.x + shape.width / 2;
  expect(Math.abs(panelCentre - shapeCentre)).toBeLessThan(4);

  // And clear of the node rather than sitting on top of it.
  expect(panel.y).toBeGreaterThan(shape.y + shape.height);
});

// The flip is the reason the position is computed rather than fixed: a
// node low on the canvas has no room for a panel under it.
test('the node panel flips above its node when there is no room below', async ({
  page,
  request,
}) => {
  const project = await createProject(page, 'E2E anchor flip');
  const node = await addNode(request, project.id, 'E2E anchor flip node');

  await page.goto(
    `/ui/project/vw?projectId=${project.id}&nodeId=${node.id}&visualizationMode=Rootless`
  );
  await expect(page.locator('#node-detail header h2')).toHaveText(node.title);
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute('transform', /translate/, {
    timeout: 10_000,
  });

  // Pan the drawing downwards until the node sits low in the canvas.
  // ArrowUp moves the content down, 60px a press.
  const canvas = page.locator('#tree-container');
  await canvas.focus();
  for (let i = 0; i < 3; i++) {
    await page.keyboard.press('ArrowUp');
  }

  // The panel tracks the node while the graph moves under it, so this
  // is the same anchoring rule resolving the other way.
  await expect
    .poll(async () => {
      const shape = await box(page, `#graph-nodes [data-node-id="${node.id}"]`);
      const panel = await box(page, '#node-panel');
      return panel.y < shape.y;
    })
    .toBe(true);
});
