import { test, expect } from '@playwright/test';
import { addNode, createProject } from './helpers';

// Every navigation here asks for `visualizationMode=Layered` explicitly
// (#223). It is not redundant: which drawing a request with no
// parameter gets is Config.Visualization's hardcoded default, and that
// default is "whichever visualization was added most recently" -- so it
// moves every time one is added. This spec is about the layered
// drawing's rects, `#node-<id>` ids and derived containment edges, and
// it should keep testing those rather than silently re-pointing at
// whatever landed last.

// Fourth and last workflow covered by this suite (#97, follow-up to
// #94-#96): view the dependency graph, click a node, and
// confirm its detail panel opens with the `.node-highlight` glow, then
// that closing the panel clears it again. The `.flash` background-poll
// effect (Node.Refresh) is explicitly out of scope here, same as the
// proposal's hazards call out -- a one-shot transient, not this spec's
// concern.
//
// Two things here changed with the radial layout (#162):
//
//   - Nodes are located by id (`#node-<id>`), not by their label text.
//     Labels now wrap to the node and truncate past three lines
//     (Data.Text.Util.wrapLabel), so a node's full title is no longer
//     present as one contiguous string to filter on -- and the id was
//     always the more robust handle anyway, being independent of how
//     the label happens to render.
//   - This uses a real click() again, not dispatchEvent('click'). The
//     workaround existed because of #120 (nodes never positioned, so
//     there was no reliable on-screen point to click); with the layout
//     now deterministic and fitted to the viewport, a real pointer
//     click works -- which also makes this a regression test for nodes
//     actually landing somewhere visible and clickable.
test("clicking a graph node opens its detail panel and highlights it, closing clears both", async ({ page, request }) => {
  const project = await createProject(page, 'E2E graph project');
  const node = await addNode(request, project.id, 'E2E graph node');

  await page.goto(`/ui/project/vw?projectId=${project.id}&visualizationMode=Layered`);

  // Settled-state check per the proposal's hazards: the graph arrives
  // by an htmx swap into #tree-container, not synchronously with
  // navigation -- assert on the rendered SVG structure (both nodes
  // present as real elements) before interacting with either, rather
  // than assuming the graph is ready right after goto(). Since #181 the
  // SVG is server-rendered, so there is no client layout pass to wait
  // on beyond that swap.
  await expect(page.locator('#graph-nodes .node')).toHaveCount(2);

  const graphNode = page.locator(`#node-${node.id}`);
  await expect(graphNode).toBeAttached();
  await expect(graphNode).not.toHaveClass(/node-highlight/);

  await graphNode.click();

  // Opens #node-panel (Node.templateNodePanel), which itself loads the
  // plain node-detail view into #node-detail -- assert on that settled
  // content, not the panel's mere presence, so this also confirms the
  // click targeted the right node.
  await expect(page.locator('#node-detail header h2')).toHaveText(node.title);

  // The highlight is hyperscript-driven, tied to the panel element's
  // own htmx lifecycle (`init add .node-highlight to #node-<id> on
  // htmx:beforeCleanupElement remove .node-highlight from #node-<id>`),
  // not server state -- asserting on the graph node's class here, not
  // anything panel-side.
  await expect(graphNode).toHaveClass(/node-highlight/);

  // Close the panel and confirm both the panel and the highlight clear.
  await page.getByRole('button', { name: 'close' }).click();
  await expect(page.locator('#node-panel')).toBeEmpty();
  await expect(graphNode).not.toHaveClass(/node-highlight/);
});

// The layout's own contract (#162): the graph must render compactly and
// legibly, not sprawl or pile nodes on top of each other. Asserting on
// geometry here rather than eyeballing a screenshot -- this is the
// property that regressed twice while building the layout.
test("the dependency graph lays nodes out on-screen without overlapping them", async ({ page, request }) => {
  const project = await createProject(page, 'E2E graph layout');
  await addNode(request, project.id, 'E2E layout node A');
  await addNode(request, project.id, 'E2E layout node B');
  await addNode(request, project.id, 'E2E layout node C');

  await page.goto(`/ui/project/vw?projectId=${project.id}&visualizationMode=Layered`);
  await expect(page.locator('#graph-nodes .node')).toHaveCount(4);

  // Boxes now, not circles (#178), and the server places them (#181):
  // the group's transform is the box's *top-left*, and its size is on
  // the rect. Reading both means this can assert real box overlap
  // rather than the centre-distance proxy the circle version used.
  const boxes = await page.locator('#graph-nodes .node').evaluateAll((els) =>
    els.map((el) => {
      const m = (el.getAttribute('transform') || '').match(/translate\(([-\d.eE]+),([-\d.eE]+)\)/);
      const rect = el.querySelector('rect');
      return {
        id: el.id,
        x: m ? parseFloat(m[1]) : NaN,
        y: m ? parseFloat(m[2]) : NaN,
        w: rect ? parseFloat(rect.getAttribute('width') || '') : NaN,
        h: rect ? parseFloat(rect.getAttribute('height') || '') : NaN,
      };
    })
  );

  // Every node positioned and sized at all -- #120's regression, where
  // every node past the first kept a null transform.
  for (const b of boxes) {
    expect(
      Number.isFinite(b.x) && Number.isFinite(b.y),
      `${b.id} has a real position`,
    ).toBe(true);
    expect(Number.isFinite(b.w) && Number.isFinite(b.h), `${b.id} has a real size`).toBe(true);
  }

  // And no two boxes overlapping, which for axis-aligned rectangles is
  // exact rather than a proxy: they overlap only if they overlap on
  // both axes at once.
  for (let i = 0; i < boxes.length; i++) {
    for (let j = i + 1; j < boxes.length; j++) {
      const a = boxes[i], b = boxes[j];
      const overlaps =
        a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
      expect(overlaps, `${a.id} and ${b.id} do not overlap`).toBe(false);
    }
  }
});

// The cutover (#181): the server-computed graph is what the app serves,
// with no query parameter. Before this, every one of #173-#180 was
// reachable only via `?layout=server`, which nothing in the UI set
// (#192) -- so this is the first test that drives any of it in a real
// browser.
test("the graph renders server-side, with no client layout script", async ({ page, request }) => {
  const project = await createProject(page, 'E2E server layout');
  await addNode(request, project.id, 'E2E server node');

  await page.goto(`/ui/project/vw?projectId=${project.id}&visualizationMode=Layered`);
  await expect(page.locator('#graph-nodes .node')).toHaveCount(2);

  // Rounded boxes, classed by kind -- what manage-project.css styles.
  await expect(page.locator('#graph-nodes .node rect.root')).toHaveCount(1);
  await expect(page.locator('#graph-nodes .node rect.work')).toHaveCount(1);
  await expect(page.locator('#graph-nodes circle')).toHaveCount(0);

  // The graph no longer leaves the server as data for a client to lay
  // out, so there is nothing for one to read.
  //
  // Note this stays true even though the viewport loads d3 again: d3
  // is there to move a transform on #graph-zoom-layer, and never sees
  // the graph's structure. "No client layout" is about where the
  // positions are computed, and they are still all computed in
  // Domain.Project.Graph.*.
  await expect(page.locator('#graph-data')).toHaveCount(0);
});

// Containment (#198, #206): the project root heads the graph, and the
// edges to its work carry an arrowhead like any dependency -- a
// project's completion does depend on its work being complete.
//
// The arrow assertion has to be an e2e test rather than a markup one.
// `marker-end` is set in two places, the path attribute and
// `manage-project.css`'s `.link` rule, so markup alone doesn't settle
// what the browser actually draws: #198 removed the attribute and the
// CSS put it straight back, while the integration test stayed green.
// Computed style is the only thing that sees the real answer.
test("the project root heads the graph, with arrows into it from its work", async ({ page, request }) => {
  const project = await createProject(page, 'E2E containment');
  for (const t of ['Containment A', 'Containment B']) {
    await addNode(request, project.id, t);
  }

  await page.goto(`/ui/project/vw?projectId=${project.id}&visualizationMode=Layered`);
  await expect(page.locator('#graph-nodes .node')).toHaveCount(3);

  const tops = await page.locator('#graph-nodes .node').evaluateAll((els) =>
    els.map((el) => {
      const m = (el.getAttribute('transform') || '').match(/translate\(([-\d.eE]+),([-\d.eE]+)\)/);
      return { root: !!el.querySelector('rect.root'), y: m ? parseFloat(m[2]) : NaN };
    })
  );

  const rootY = tops.find((t) => t.root)?.y;
  const workYs = tops.filter((t) => !t.root).map((t) => t.y);
  expect(rootY, 'the root node is present and positioned').not.toBeUndefined();
  expect(workYs.length).toBe(2);
  for (const y of workYs) {
    expect(y, 'work sits below the root').toBeGreaterThan(rootY!);
  }

  // Every edge resolves to a real marker in the browser, CSS included.
  const markers = await page
    .locator('#graph-links path')
    .evaluateAll((els) => els.map((el) => getComputedStyle(el).markerEnd));
  expect(markers.length).toBeGreaterThan(0);
  for (const m of markers) {
    expect(m, 'every edge carries an arrowhead').not.toBe('none');
  }
});


// The viewport, driven for the first time here for the same reason as
// above.
//
// Panning and zooming are a transform on #graph-zoom-layer, written by
// d3-zoom -- not the container's scroll position and not the SVG's
// width/height, which is what the pre-d3 viewport moved. So everything
// below reads that one attribute.
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

test("the graph viewport opens on the project root and zooms", async ({ page, request }) => {
  const project = await createProject(page, 'E2E viewport');
  for (const t of ['Viewport node A', 'Viewport node B', 'Viewport node C']) {
    await addNode(request, project.id, t);
  }

  await page.goto(`/ui/project/vw?projectId=${project.id}&visualizationMode=Layered`);
  await expect(page.locator('#graph-nodes .node')).toHaveCount(4);

  // The transform only appears once d3-zoom has loaded and applied the
  // opening view, which is a dynamic import -- so this is also the
  // assertion that the vendored bundles actually load and run.
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute(
    'transform',
    /translate/,
    { timeout: 10_000 }
  );

  // Opens at natural size -- deliberately not scaled to fit, which is
  // what would shrink titles past legibility on a big project.
  const opened = await layerTransform(page);
  expect(opened.k).toBeCloseTo(1, 2);

  // ...and with the project root centred in the container. The server
  // emits where it put the root; the viewport's job is to translate it
  // to the middle.
  const svg = page.locator('#tree-view');
  const rootX = parseFloat((await svg.getAttribute('data-root-x')) || '');
  const rootY = parseFloat((await svg.getAttribute('data-root-y')) || '');
  const box = await page.locator('#tree-container').boundingBox();
  if (!box) throw new Error('#tree-container has no box');
  expect(opened.x).toBeCloseTo(box.width / 2 - rootX, 0);
  expect(opened.y).toBeCloseTo(box.height / 2 - rootY, 0);

  // Zoom via the keyboard, which is what replaced the +/- buttons.
  await page.locator('#tree-container').focus();
  await page.keyboard.press('+');
  await expect
    .poll(async () => (await layerTransform(page)).k)
    .toBeGreaterThan(opened.k);

  const zoomedIn = (await layerTransform(page)).k;
  await page.keyboard.press('-');
  await expect
    .poll(async () => (await layerTransform(page)).k)
    .toBeLessThan(zoomedIn);

  // `0` resets outright, the way the recentre button used to.
  await page.keyboard.press('+');
  await page.keyboard.press('0');
  await expect.poll(async () => (await layerTransform(page)).k).toBeCloseTo(1, 2);
  const reset = await layerTransform(page);
  expect(reset.x).toBeCloseTo(box.width / 2 - rootX, 0);
});

// Ctrl+wheel is pinch-to-zoom on a trackpad, and a plain wheel pans
// rather than zooming -- the pair of gestures that carry the zoom now
// that there are no buttons.
test("ctrl+wheel zooms about the pointer and a plain wheel pans", async ({ page, request }) => {
  const project = await createProject(page, 'E2E wheel');
  for (const t of ['Wheel node A', 'Wheel node B']) {
    await addNode(request, project.id, t);
  }

  await page.goto(`/ui/project/vw?projectId=${project.id}&visualizationMode=Layered`);
  await expect(page.locator('#graph-nodes .node')).toHaveCount(3);
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute(
    'transform',
    /translate/,
    { timeout: 10_000 }
  );

  const box = await page.locator('#tree-container').boundingBox();
  if (!box) throw new Error('#tree-container has no box');
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);

  const before = await layerTransform(page);

  // Plain wheel pans: the scale must not move.
  await page.mouse.wheel(0, 120);
  await expect
    .poll(async () => (await layerTransform(page)).y)
    .toBeLessThan(before.y);
  expect((await layerTransform(page)).k).toBeCloseTo(before.k, 2);

  // Ctrl+wheel zooms.
  const panned = await layerTransform(page);
  await page.keyboard.down('Control');
  await page.mouse.wheel(0, -120);
  await page.keyboard.up('Control');
  await expect
    .poll(async () => (await layerTransform(page)).k)
    .toBeGreaterThan(panned.k);
});

// Pointer-drag panning, and the hazard it introduces: every node is
// also a click target, so a drag must not read as a click and open a
// node's panel on the way past.
test("dragging the canvas pans it without opening a node", async ({ page, request }) => {
  const project = await createProject(page, 'E2E pan');
  for (const t of ['Pan node A', 'Pan node B', 'Pan node C', 'Pan node D']) {
    await addNode(request, project.id, t);
  }

  await page.goto(`/ui/project/vw?projectId=${project.id}&visualizationMode=Layered`);
  await expect(page.locator('#graph-nodes .node')).toHaveCount(5);
  await expect(page.locator('#graph-zoom-layer')).toHaveAttribute(
    'transform',
    /translate/,
    { timeout: 10_000 }
  );

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
