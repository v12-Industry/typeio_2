import { test, expect } from '@playwright/test';
import { addNode, createProject } from './helpers';

// Changing a node's status:
// change a node's status via the status <select> in the node-detail
// panel, and confirm it both updates the panel's own indicator and
// actually persists (re-fetch the panel and check the new status is
// selected there too, not just that the indicator claimed success).
//
// Same deep-link approach as edit-node.spec.ts for opening the
// panel (?nodeId= in the URL, not clicking the graph) -- see that
// spec's comments for why.
test("changing a node's status updates and persists it", async ({ page, request }) => {
  const project = await createProject(page, 'E2E node-status project');
  const node = await addNode(request, project.id, 'E2E node-status');

  await page.goto(`/ui/project/vw?projectId=${project.id}&nodeId=${node.id}&visualizationMode=Layered`);
  await page.getByRole('button', { name: 'mode_edit' }).click();

  // A new node is seeded "active" (Api.Node.Post.handlePostNode always
  // queries the "active" NodeStatus). Pick a different one from the
  // same reference data `make seed-db` provides
  // (Domain.Central.Responder.Api.Seed.nodeStatuses).
  //
  // click() before selectOption(), not selectOption() alone: confirmed
  // by direct testing that calling selectOption() on this <select>
  // immediately after it's htmx-swapped into the DOM never fires its
  // hx-trigger="change" PUT -- no request, ever. Explicitly clicking
  // the element first (even though selectOption() doesn't require a
  // prior click to work in general) makes it fire reliably every time;
  // an artificial wait between the two does not fix it on its own, so
  // this isn't a settle-timing issue -- see e2e/README.md's Notes for
  // the general shape of this hazard (freshly htmx-swapped-in elements
  // and Playwright's non-pointer interaction helpers).
  //
  // getByLabel(), not a name-attribute selector: the control carries
  // <select>'s missing id alongside the title/description fields it
  // was filed for -- same underlying gap, same file.
  const status = page.getByLabel('Status:');
  await status.click();
  await status.selectOption('closed');

  // Assert on the settled success icon (Node.Status.templatePostSuccess's
  // literal "done" ligature) in #status-indicator, per the proposal's
  // "never assert mid-swap" convention.
  await expect(page.locator('#status-indicator i.material-icons')).toHaveText('done');

  // Confirms it actually persisted, not just that the indicator claimed
  // success -- via the plain (non-edit) node-detail view's Status text.
  await page.getByRole('button', { name: 'check' }).click();
  const statusRow = page.locator('#node-detail #node-properties article').filter({ hasText: 'Status:' });
  await expect(statusRow.locator('.property-value')).toHaveText('closed');

  // Also reopen the edit panel and confirm the dropdown itself now
  // shows the real current status pre-selected. `selected` has to be
  // on the matching <option>, not on the <select> itself: the latter
  // isn't meaningful HTML, and every browser ignores it and defaults to
  // whichever <option> comes first regardless of the node's real
  // status. Re-navigating
  // (rather than clicking mode_edit again) is deliberate: it forces a
  // fresh GET of the edit panel from the server, not a reused DOM node.
  await page.goto(`/ui/project/vw?projectId=${project.id}&nodeId=${node.id}&visualizationMode=Layered`);
  await page.getByRole('button', { name: 'mode_edit' }).click();
  await expect(page.getByLabel('Status:')).toHaveValue('closed');
});
