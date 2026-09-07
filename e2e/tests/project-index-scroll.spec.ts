import { test, expect } from '@playwright/test';
import { createProject, createProjectFast } from './helpers';

// #container (the app shell) is pinned to overflow:hidden with
// nothing else in the ancestor chain ever set to scroll, so a project
// index with more rows than fit on screen had no user-facing way to
// reach the rest -- present in the DOM (confirmed in the ticket by
// `container.scrollTop = ...` from a console, which still worked),
// unreachable by wheel, trackpad, scrollbar or keyboard. Fixed by
// giving #view (global.css) the scroll region instead of #container,
// which has to stay pinned to the viewport for the app's SPA-like
// shell behaviour -- see docs/development/ui/components.md.
//
// Seeds enough filler projects to force real overflow, comfortably past
// what the ticket's own 1280x800/~29-project reproduction needed, so
// this holds regardless of how many rows a previous local run already
// left behind (this suite doesn't reset the database between runs --
// see e2e/README.md) or how many other specs are creating projects of
// their own at the same time (`fullyParallel` in playwright.config.ts).
// createProjectFast() is used rather than createProject(): this test is
// about scrolling the list, not about creating a project.
const FILLER_PROJECTS = 30;

test('the project index can be scrolled to its last card by wheel', async ({ page, request }) => {
  await Promise.all(
    Array.from({ length: FILLER_PROJECTS }, (_, i) =>
      createProjectFast(request, `E2E index-scroll filler ${i}`)
    )
  );

  await page.goto('/ui/projects/vw');

  const cards = page.locator('.project-item');
  await expect(cards.first()).toBeVisible();

  // Whichever card renders last -- oldest by lastUpdated among the
  // rows the index shows (Domain.Project.Responder.Ui.ProjectIndex.List.queryProjectVw
  // orders by lastUpdated desc) -- is the bottom-right-most cell in the
  // 4-column grid, so it's the one furthest past the fold regardless of
  // which specific projects ended up in that top-50 window.
  const lastCard = cards.last();

  // Reproduces the bug as a baseline: with this many rows, the last
  // card starts out of view.
  await expect(lastCard).not.toBeInViewport();

  // A real wheel event, not scrollIntoView() -- the ticket's own
  // finding was that programmatic scrolling already worked even while
  // this was broken (`overflow: hidden` doesn't block `el.scrollTop =`),
  // so scrollIntoViewIfNeeded() would pass against the bug too. Several
  // modest deltas, closer to what an actual wheel produces than one
  // giant jump.
  await page.mouse.move(640, 400);
  for (let i = 0; i < 20; i++) {
    await page.mouse.wheel(0, 400);
  }

  await expect(lastCard).toBeInViewport();
});

// The second half of the same rule: #view (global.css) scrolls by
// default, and the dependency graph page has to opt out
// (views/manage-project.css) since its own viewport pans by transform
// on #graph-zoom-layer and must not also become a native scroll target
// underneath it.
//
// Asserted on computed style directly rather than by wheeling over the
// graph and checking it doesn't move -- graph-viewport.js's own wheel
// handler already calls preventDefault() to drive its pan/zoom, which
// would mask whether the opt-out CSS rule is actually present. Computed
// style is what graph.spec.ts's arrowhead test reaches for in the same
// situation (a markup assertion passing straight through what the
// browser actually renders), for the same reason.
test("the graph page's #view stays non-scrolling", async ({ page }) => {
  const project = await createProject(page, 'E2E index-scroll graph opt-out');
  await page.goto(`/ui/project/vw?projectId=${project.id}&visualizationMode=Layered`);

  await expect(page.locator('#tree-container')).toBeVisible();

  const overflowY = await page
    .locator('#view')
    .evaluate((el) => getComputedStyle(el).overflowY);
  expect(overflowY).toBe('hidden');
});
