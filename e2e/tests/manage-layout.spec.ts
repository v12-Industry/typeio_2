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
// and is not visible in the markup the server sends. Rootless is pinned
// for the same reason graph-viewport.spec.ts pins it: the default
// visualization moves, and this needs exactly one shape per node.
//
// Both numbers below are the ones node-panel-anchor.js places with.
const GAP = 14;
const MARGIN = 12;
// One arrow press, from graph-viewport.js's KEY_PAN_STEP.
const PAN_STEP = 60;

const geometry = async (page: import('@playwright/test').Page, nodeId: string) => ({
  panel: await box(page, '#node-panel'),
  shape: await box(page, `#graph-nodes [data-node-id="${nodeId}"]`),
  frame: await box(page, '#view'),
});

// Which side of its node the panel is on. `overlapping` is a failure in
// every case here, and naming it is what makes that failure readable.
const side = async (page: import('@playwright/test').Page, nodeId: string) => {
  const { panel, shape } = await geometry(page, nodeId);
  if (panel.y + panel.height <= shape.y + 1) return 'above';
  if (panel.y >= shape.y + shape.height - 1) return 'below';
  return 'overlapping';
};

test('the open node panel is anchored to its node', async ({ page, request }) => {
  const project = await createProject(page, 'E2E anchor');
  const node = await addNode(request, project.id, 'E2E anchor node');

  await page.goto(
    `/ui/project/vw?projectId=${project.id}&nodeId=${node.id}&visualizationMode=Rootless`
  );
  await expect(page.locator('#node-detail header h2')).toHaveText(node.title);
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute('transform', /translate/, {
    timeout: 10_000,
  });

  // Polled: the placement runs off a requestAnimationFrame, so the
  // first paint after the swap can still be at the fallback corner.
  await expect
    .poll(async () => {
      const { panel, shape } = await geometry(page, node.id);
      return Math.abs(panel.x + panel.width / 2 - (shape.x + shape.width / 2));
    })
    .toBeLessThan(4);

  // Clear of the node rather than sitting on top of it. Which side it
  // lands on is not asserted here -- that depends on how much room this
  // viewport leaves under the node, and is the next test's subject.
  expect(await side(page, node.id)).not.toBe('overlapping');

  // ...and wholly on the canvas, not trailing off the edge after a node
  // that is near one.
  const { panel, frame } = await geometry(page, node.id);
  expect(panel.x).toBeGreaterThanOrEqual(frame.x - 1);
  expect(panel.y).toBeGreaterThanOrEqual(frame.y - 1);
  expect(panel.x + panel.width).toBeLessThanOrEqual(frame.x + frame.width + 1);
  expect(panel.y + panel.height).toBeLessThanOrEqual(frame.y + frame.height + 1);
});

// The panel tracks its node while the graph moves under it, and flips
// sides when the room underneath runs out. The flip is the whole reason
// the position is computed rather than fixed.
test('the panel follows its node, flipping sides to stay on the canvas', async ({
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
  await expect.poll(async () => side(page, node.id)).not.toBe('overlapping');

  const canvas = page.locator('#tree-container');
  await canvas.focus();

  // Horizontal: pan sideways and the panel goes with its node rather
  // than staying where it was opened.
  const before = await geometry(page, node.id);
  await page.keyboard.press('ArrowRight');
  await expect
    .poll(async () => (await geometry(page, node.id)).shape.x)
    .toBeLessThan(before.shape.x);
  await expect
    .poll(async () => {
      const { panel, shape } = await geometry(page, node.id);
      return Math.abs(panel.x + panel.width / 2 - (shape.x + shape.width / 2));
    })
    .toBeLessThan(4);

  // Vertical: how far the node has to rise for a panel of this height
  // to fit underneath it. Computed rather than guessed, because the
  // panel's height comes from its contents and the canvas's from the
  // viewport -- a fixed number of presses would be a bet on both.
  const { panel, shape, frame } = await geometry(page, node.id);
  const overshoot =
    shape.y + shape.height + GAP + panel.height - (frame.y + frame.height - MARGIN);
  const presses = Math.max(1, Math.ceil(overshoot / PAN_STEP));

  // ArrowDown moves the drawing up, so the node rises.
  for (let i = 0; i < presses; i++) {
    await page.keyboard.press('ArrowDown');
  }
  await expect.poll(async () => side(page, node.id)).toBe('below');

  // And back the other way: with the node low again there is no room
  // under it, so the panel flips above.
  for (let i = 0; i < presses * 2; i++) {
    await page.keyboard.press('ArrowUp');
  }
  await expect.poll(async () => side(page, node.id)).toBe('above');
});
