import { test, expect } from '@playwright/test';
import { addNode, createProject } from './helpers';

// The graph viewport's gestures, which belong to graph-viewport.js
// rather than to any one drawing: keyboard zoom, ctrl+wheel zoom
// against a plain wheel pan, and pointer-drag panning.
//
// Every navigation asks for `visualizationMode=Rootless` explicitly.
// That is not redundant: a request with no parameter gets
// Config.Visualization's hardcoded default, and that default is
// "whichever visualization was added most recently", so it moves. These
// gestures are the same whichever drawing is underneath, and pinning
// one keeps the node counts below predictable.
//
// Rootless draws the project's work and nothing else, so the counts
// here are exactly the number of nodes seeded -- there is no project
// root in the drawing to account for.
//
// Panning and zooming are a transform on #graph-zoom-layer, written by
// d3-zoom -- not the container's scroll position and not the SVG's
// width/height. So everything below reads that one attribute.
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

test('the graph viewport opens at natural size and zooms from the keyboard', async ({
  page,
  request,
}) => {
  const project = await createProject(page, 'E2E viewport');
  for (const t of ['Viewport node A', 'Viewport node B', 'Viewport node C']) {
    await addNode(request, project.id, t);
  }

  await page.goto(`/ui/project/vw?projectId=${project.id}&visualizationMode=Rootless`);
  await expect(page.locator('#graph-nodes .node')).toHaveCount(3);

  // The transform only appears once d3-zoom has loaded and applied the
  // opening view, which is a dynamic import -- so this is also the
  // assertion that the vendored bundles actually load and run.
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute('transform', /translate/, {
    timeout: 10_000,
  });

  // Opens at natural size -- deliberately not scaled to fit, which is
  // what would shrink titles past legibility on a big project.
  const opened = await layerTransform(page);
  expect(opened.k).toBeCloseTo(1, 2);

  // Zoom via the keyboard: the non-pointer path to the same gestures.
  await page.locator('#tree-container').focus();
  await page.keyboard.press('+');
  await expect.poll(async () => (await layerTransform(page)).k).toBeGreaterThan(opened.k);

  const zoomedIn = (await layerTransform(page)).k;
  await page.keyboard.press('-');
  await expect.poll(async () => (await layerTransform(page)).k).toBeLessThan(zoomedIn);

  // `0` resets the zoom outright.
  await page.keyboard.press('+');
  await page.keyboard.press('0');
  await expect.poll(async () => (await layerTransform(page)).k).toBeCloseTo(1, 2);
});

// Ctrl+wheel is pinch-to-zoom on a trackpad, and a plain wheel pans
// rather than zooming -- the pair of gestures that carry the zoom, there
// being no on-screen buttons.
test('ctrl+wheel zooms about the pointer and a plain wheel pans', async ({ page, request }) => {
  const project = await createProject(page, 'E2E wheel');
  for (const t of ['Wheel node A', 'Wheel node B']) {
    await addNode(request, project.id, t);
  }

  await page.goto(`/ui/project/vw?projectId=${project.id}&visualizationMode=Rootless`);
  await expect(page.locator('#graph-nodes .node')).toHaveCount(2);
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute('transform', /translate/, {
    timeout: 10_000,
  });

  const box = await page.locator('#tree-container').boundingBox();
  if (!box) throw new Error('#tree-container has no box');
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);

  const before = await layerTransform(page);

  // Plain wheel pans: the scale must not move.
  await page.mouse.wheel(0, 120);
  await expect.poll(async () => (await layerTransform(page)).y).toBeLessThan(before.y);
  expect((await layerTransform(page)).k).toBeCloseTo(before.k, 2);

  // Ctrl+wheel zooms.
  const panned = await layerTransform(page);
  await page.keyboard.down('Control');
  await page.mouse.wheel(0, -120);
  await page.keyboard.up('Control');
  await expect.poll(async () => (await layerTransform(page)).k).toBeGreaterThan(panned.k);
});

// Pointer-drag panning, and the hazard it introduces: every node is
// also a click target, so a drag must not read as a click and open a
// node's panel on the way past.
test('dragging the canvas pans it without opening a node', async ({ page, request }) => {
  const project = await createProject(page, 'E2E pan');
  for (const t of ['Pan node A', 'Pan node B', 'Pan node C', 'Pan node D']) {
    await addNode(request, project.id, t);
  }

  await page.goto(`/ui/project/vw?projectId=${project.id}&visualizationMode=Rootless`);
  await expect(page.locator('#graph-nodes .node')).toHaveCount(4);
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute('transform', /translate/, {
    timeout: 10_000,
  });

  const container = page.locator('#tree-container');
  const before = (await layerTransform(page)).x;

  const box = await container.boundingBox();
  if (!box) throw new Error('#tree-container has no box');
  const midY = box.y + box.height / 2;

  await page.mouse.move(box.x + box.width * 0.7, midY);
  await page.mouse.down();
  // Several small steps rather than one jump: a drag is a stream of
  // pointermove events, and one teleporting move is not what a real
  // pointer produces.
  for (let i = 1; i <= 5; i++) {
    await page.mouse.move(box.x + box.width * 0.7 - i * 30, midY);
  }
  await page.mouse.up();

  // Dragging left moves the drawing left, so the translate decreases.
  await expect.poll(async () => (await layerTransform(page)).x).toBeLessThan(before);

  // The drag must not have been read as a click on whatever was under
  // the pointer.
  await expect(page.locator('#node-panel')).toBeEmpty();
});
