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

  // Vertical: drive the node to each end of the canvas rather than
  // pressing a fixed number of times. Which side the panel takes is
  // decided by which side has more room, so putting the node clearly
  // into the top fifth and then the bottom fifth settles it whatever
  // the panel's contents make it -- a press count computed from its
  // height would be a bet on that height and on the viewport's.
  const panTo = async (fraction: number) => {
    const { shape, frame } = await geometry(page, node.id);
    const target = frame.y + frame.height * fraction;
    // ArrowDown moves the drawing up, so the node rises.
    const key = target < shape.y ? 'ArrowDown' : 'ArrowUp';
    const presses = Math.ceil(Math.abs(shape.y - target) / PAN_STEP);
    for (let i = 0; i < presses; i++) {
      await page.keyboard.press(key);
    }
  };

  // High on the canvas: far more room below than above, so below.
  await panTo(0.2);
  await expect.poll(async () => side(page, node.id)).toBe('below');

  // Low on the canvas: the room underneath is gone, so it flips above.
  await panTo(0.8);
  await expect.poll(async () => side(page, node.id)).toBe('above');
});

// Selecting a node brings it into view. That is visible only in the
// transform -- the drawing the server sends is the same either way --
// so a browser is the only tier that can see it at all.
const layerTransform = async (page: import('@playwright/test').Page) => {
  const raw = await page.locator('#graph-zoom-layer').getAttribute('transform');
  // d3 writes "translate(x,y) scale(k)", and omits scale at k === 1.
  const t = /translate\(\s*([-\d.e]+)\s*,\s*([-\d.e]+)\s*\)/.exec(raw ?? '');
  const s = /scale\(\s*([-\d.e]+)\s*\)/.exec(raw ?? '');
  return {
    x: t ? parseFloat(t[1]) : 0,
    y: t ? parseFloat(t[2]) : 0,
    k: s ? parseFloat(s[1]) : 1,
  };
};

const onCanvas = async (page: import('@playwright/test').Page, nodeId: string) => {
  const { shape, frame } = await geometry(page, nodeId);
  return (
    shape.x >= frame.x &&
    shape.y >= frame.y &&
    shape.x + shape.width <= frame.x + frame.width &&
    shape.y + shape.height <= frame.y + frame.height
  );
};

test('selecting a node parked off the canvas brings it into view', async ({ page, request }) => {
  const project = await createProject(page, 'E2E reveal');
  const node = await addNode(request, project.id, 'E2E reveal node');

  // A view left far from the drawing -- what a stale link, or a pan
  // somebody walked away from, leaves behind. The node is nowhere near
  // the canvas when the page arrives.
  await page.goto(
    `/ui/project/vw?projectId=${project.id}&nodeId=${node.id}` +
      `&visualizationMode=Rootless&viewX=-1800&viewY=-1400&viewScale=1`
  );
  await expect(page.locator('#node-detail header h2')).toHaveText(node.title);
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute('transform', /translate/, {
    timeout: 10_000,
  });

  // Polled: the reveal runs off the same requestAnimationFrame the
  // opening transform does, so the first paint can still be the view
  // the URL asked for.
  await expect.poll(async () => onCanvas(page, node.id)).toBe(true);

  // ...and the panel that asked for the reveal is clear of the node it
  // has just brought on screen, rather than parked on top of it.
  await expect.poll(async () => side(page, node.id)).not.toBe('overlapping');
});

test('selecting a node already in view does not move the graph', async ({ page, request }) => {
  const project = await createProject(page, 'E2E reveal steady');
  const node = await addNode(request, project.id, 'E2E reveal steady node');

  // The opening view, with nothing selected. It centres the drawing, so
  // this single node is comfortably on the canvas already.
  await page.goto(`/ui/project/vw?projectId=${project.id}&visualizationMode=Rootless`);
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute('transform', /translate/, {
    timeout: 10_000,
  });
  const opening = await layerTransform(page);

  // The same view, with the node selected. A reveal that recentred
  // rather than nudging would show up here as a jump.
  await page.goto(
    `/ui/project/vw?projectId=${project.id}&nodeId=${node.id}&visualizationMode=Rootless`
  );
  await expect(page.locator('#node-detail header h2')).toHaveText(node.title);
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute('transform', /translate/, {
    timeout: 10_000,
  });
  await expect.poll(async () => onCanvas(page, node.id)).toBe(true);

  const after = await layerTransform(page);
  expect(after.x).toBeCloseTo(opening.x, 1);
  expect(after.y).toBeCloseTo(opening.y, 1);
  expect(after.k).toBeCloseTo(opening.k, 2);

  // And nothing was written to the URL: the view was never adjusted, so
  // it stays the plain link it was reached by.
  expect(new URL(page.url()).searchParams.get('viewScale')).toBeNull();
});
