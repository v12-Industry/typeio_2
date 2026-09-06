import { test, expect, Page } from '@playwright/test';

// E2E coverage for the orbital dependency-weighted visualization (#240,
// specified in #229).
//
// This spec asks for its drawing by name, with `?visualizationMode=
// Orbital` on the page URL (#223) -- the same server serves every
// visualization, and the parameter is forwarded from the page to the
// htmx request that actually fetches the graph fragment.
//
// It briefly needed a second server on its own port, back when the
// choice came from GRAPH_VISUALIZATION at boot; that is gone along with
// the variable.
//
// Everything here is about a node being drawn MORE THAN ONCE, which no
// other visualization does and therefore no other spec covers:
//
//   - the unit tier proves the geometry (Orbit.LayoutSpec),
//   - the integration tier proves the markup (Orbital.ResponderSpec),
//   - and only a browser can prove that hyperscript's `to <selector/>`
//     really does reach every replica, that an hx-target swap lands on
//     the right one of several, and that the discs are actually
//     clickable where they were placed.
//
// The fixture is the seeded demo project (#243) rather than one built
// here: replication needs a node with several dependents, and until
// #205 there is no way to create a dependency through the app at all.

// Title of the demo project the seed inserts. Its shape is deliberate
// -- three heads and one node three separate outcomes wait on -- see
// Domain.Central.Responder.Api.Seed.
const DEMO_PROJECT = 'Public API launch';

async function demoProjectId(page: Page): Promise<string> {
  await page.goto('/ui/projects/vw');
  const card = page.locator('.project-item').filter({ hasText: DEMO_PROJECT });
  await expect(
    card.getByRole('heading', { name: DEMO_PROJECT, level: 3 })
  ).toBeVisible();
  return (await card.locator('.id').innerText()).trim();
}

// Opens the demo project's graph and waits for the drawing to settle.
//
// Settled-state check per e2e-testing.md's hazards: the graph arrives by
// an htmx swap into #tree-container, not synchronously with navigation.
// Waiting on a disc being attached is the same discipline graph.spec.ts
// uses for `.node`.
async function openGraph(page: Page): Promise<string> {
  const projectId = await demoProjectId(page);
  await page.goto(
    `/ui/project/vw?projectId=${projectId}&visualizationMode=Orbital`
  );
  await expect(page.locator('#graph-nodes .disc').first()).toBeAttached();
  return projectId;
}

// The node id that the drawing renders more than once, and how many
// discs it got. Read from the DOM rather than hardcoded: the seed's
// node ids are serial and would differ on any database that had other
// projects created first.
async function replicatedNode(page: Page): Promise<{ id: string; count: number }> {
  const counts = await page.evaluate(() => {
    const seen: Record<string, number> = {};
    for (const el of document.querySelectorAll('#graph-nodes .disc')) {
      const id = el.getAttribute('data-node-id')!;
      seen[id] = (seen[id] ?? 0) + 1;
    }
    return seen;
  });
  const entry = Object.entries(counts).find(([, n]) => n > 1);
  expect(
    entry,
    'the seeded demo project should contain a node with several dependents'
  ).toBeTruthy();
  return { id: entry![0], count: entry![1] };
}

test('a node with several dependents is drawn once per dependent', async ({ page }) => {
  await openGraph(page);

  const { id, count } = await replicatedNode(page);
  expect(count).toBeGreaterThan(1);

  // Same node, so one data-node-id...
  await expect(page.locator(`#graph-nodes .disc[data-node-id="${id}"]`)).toHaveCount(
    count
  );

  // ...but distinct element ids, one per replica. Both halves matter:
  // shared identity is what the Project Manage hooks select on, and
  // distinct ids are what keeps the label refresh landing on the right
  // circle. Get either wrong and the drawing still renders.
  const elementIds = await page
    .locator(`#graph-nodes .disc[data-node-id="${id}"]`)
    .evaluateAll((els) => els.map((e) => e.id));
  expect(new Set(elementIds).size).toBe(count);
  for (const elementId of elementIds) {
    expect(elementId).toMatch(new RegExp(`^disc-${id}-\\d+$`));
  }

  // And nothing carries the layered drawing's id scheme -- a stale
  // `#node-<id>` query should find nothing here rather than silently
  // matching one arbitrary replica.
  await expect(page.locator(`#node-${id}`)).toHaveCount(0);
});

test('hovering one replica highlights every replica of that node', async ({ page }) => {
  await openGraph(page);
  const { id, count } = await replicatedNode(page);

  const discs = page.locator(`#graph-nodes .disc[data-node-id="${id}"]`);
  await expect(discs.first()).not.toHaveClass(/replica-hover/);

  await discs.first().hover();

  // The point of the whole feature: one pointer, every copy. CSS cannot
  // express this -- there is no selector for "every element sharing an
  // attribute value with the hovered one" -- so it is hyperscript on
  // the disc, and only a browser can prove it resolves.
  for (let i = 0; i < count; i++) {
    await expect(discs.nth(i)).toHaveClass(/replica-hover/);
  }

  // Leaving clears it. Also a guard against the flicker loop that
  // `pointer-events: none` on this class would cause: if the shape left
  // hit-testing under the cursor, the class would oscillate rather than
  // settle.
  await page.mouse.move(0, 0);
  for (let i = 0; i < count; i++) {
    await expect(discs.nth(i)).not.toHaveClass(/replica-hover/);
  }
});

test('clicking any replica opens the node panel and highlights them all', async ({
  page,
}) => {
  await openGraph(page);
  const { id, count } = await replicatedNode(page);
  const discs = page.locator(`#graph-nodes .disc[data-node-id="${id}"]`);

  // Clicking the *last* replica, not the first: they are the same node
  // and must behave identically, and a bug that wired only the first
  // one would pass if this always clicked the first.
  await discs.nth(count - 1).click();

  await expect(page.locator('#node-detail header h2')).toBeVisible();

  // The panel's highlight is a different class from the hover one
  // (.node-highlight vs .replica-hover) precisely so the two cannot
  // clobber each other -- and it has to reach every replica too.
  for (let i = 0; i < count; i++) {
    await expect(discs.nth(i)).toHaveClass(/node-highlight/);
  }
});

test('editing a title updates the label on every replica', async ({ page }) => {
  await openGraph(page);
  const { id, count } = await replicatedNode(page);
  const discs = page.locator(`#graph-nodes .disc[data-node-id="${id}"]`);

  await discs.first().click();
  await expect(page.locator('#node-detail header h2')).toBeVisible();
  await page.getByRole('button', { name: 'mode_edit' }).click();

  // A fixed-shape title rather than one appended to whatever is there,
  // so re-running this against a database that is not freshly seeded
  // does not accumulate suffixes on the seed's own node.
  const newTitle = `Orbital e2e ${Date.now()}`;

  // selectText() + pressSequentially(), not fill(): edit-node.spec.ts
  // establishes by direct testing that fill() never fires htmx's
  // `input changed delay:500ms` trigger on these fields -- no PUT, ever
  // -- and that clearing with fill('') suppresses it even for real
  // keystrokes that follow.
  const title = page.getByLabel('Title:');
  await title.selectText();
  await title.pressSequentially(newTitle);

  // Settle on the success indicator, never the mid-debounce spinner.
  await expect(
    page.locator('label[for="title"] .indicator-box i.material-icons')
  ).toHaveText('done');

  // Closing the edit fires nodePanel:onEditClosed, which is what the
  // per-disc refresh hooks listen for.
  await page.getByRole('button', { name: 'check' }).click();
  await expect(page.locator('#node-detail header h2')).toHaveText(newTitle);

  // The assertion this test exists for. An hx-target swaps exactly one
  // element however many match, so this only passes if each replica
  // carries its own hook aimed at its own label -- the whole of #244.
  for (let i = 0; i < count; i++) {
    await expect(discs.nth(i).locator('text')).toContainText('Orbital e2e');
  }
});

test('the drawing places every disc clear of the others', async ({ page }) => {
  await openGraph(page);

  // The no-overlap invariant is unit-tested against the geometry, but
  // that proves the coordinates rather than what the browser drew --
  // this is the same check graph.spec.ts's own overlap assertion makes
  // for the layered drawing, on real rendered boxes.
  const boxes = await page
    .locator('#graph-nodes .disc circle')
    .evaluateAll((els) =>
      els.map((e) => {
        const b = (e as SVGGraphicsElement).getBoundingClientRect();
        return { x: b.x, y: b.y, w: b.width, h: b.height };
      })
    );
  expect(boxes.length).toBeGreaterThan(1);

  for (let i = 0; i < boxes.length; i++) {
    for (let j = i + 1; j < boxes.length; j++) {
      const a = boxes[i];
      const b = boxes[j];
      const overlaps =
        a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
      expect(overlaps, `discs ${i} and ${j} overlap`).toBe(false);
    }
  }
});

test('the viewport pans the drawing without reloading it', async ({ page }) => {
  await openGraph(page);

  // graph-viewport.js is shared and unmodified by this visualization --
  // it arrives from the same graphFrame (#242). Worth one check that it
  // is actually wired up here, since a drawing that renders but cannot
  // be navigated is not much use on a large project.
  const layer = page.locator('#graph-zoom-layer');
  await expect(layer).toBeAttached();

  const before = await layer.getAttribute('transform');

  await page.locator('#tree-container').focus();
  for (let i = 0; i < 3; i++) {
    await page.keyboard.press('ArrowRight');
  }

  await expect(async () => {
    expect(await layer.getAttribute('transform')).not.toBe(before);
  }).toPass();
});
