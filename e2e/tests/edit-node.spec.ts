import { test, expect } from '@playwright/test';
import { addNode, createProject } from './helpers';

// Editing a node, building on the
// create-project pilot): add a node, then edit its title and
// description via the node-detail panel.
//
// The "add a node" step here is a direct API call
// (helpers.ts's addNode()), not a UI interaction: the app has no UI
// affordance to create a node at all -- see that helper's comments for
// the full finding. Reusing it as setup, the same way the create suite
// reuses `make seed-db` for reference data rather than reinventing
// seeding, keeps this spec focused on what's actually UI-testable here:
// editing.
//
// Opening the node panel goes through the URL's `nodeId` query param
// (ProjectManage.View's own supported deep-link shape -- the same one
// Graph.pushUrl puts in the address bar on a real click) rather than
// clicking the node in the graph. That's deliberate, not a workaround:
// interacting with the graph itself is graph.spec.ts's scope,
// and the direct-link path exercises a real, already-supported way into
// this same panel without depending on where a node lands.
//
// A real click would work here too -- the server places every node
// deterministically, and graph.spec.ts does exactly that. This spec
// stays deep-linked because that is the narrower thing to test.
test('editing a node updates its title and description', async ({ page, request }) => {
  const project = await createProject(page, 'E2E edit-node project');
  const node = await addNode(request, project.id, 'E2E edit-node');
  const nodeTitle = node.title;

  await page.goto(`/ui/project/vw?projectId=${project.id}&nodeId=${node.id}&visualizationMode=Layered`);

  // Opens the node panel (#node-panel), which itself loads the
  // non-editable detail view into #node-detail. Switch to the editable
  // form via the pencil-icon button (Node.templateNodePanel) -- its
  // accessible name is the Material Icons ligature text itself
  // ("mode_edit"), not a rendered glyph, so this is a real DOM text
  // match, not something that depends on how the icon font renders.
  await page.getByRole('button', { name: 'mode_edit' }).click();

  const newTitle = `${nodeTitle} (edited)`;
  const newDescription = `Edited by e2e/tests/edit-node.spec.ts at ${new Date().toISOString()}`;

  // getByLabel() -- the title input carries the id "title" (it used
  // to be "node-title", not matching its <label for="title">) and gave
  // the description textarea an id at all (it had none).
  //
  // selectText() + pressSequentially(), not fill(): confirmed by direct
  // testing that fill() never fires htmx's `input changed delay:500ms`
  // trigger on these fields at all -- no PUT request, ever, no matter
  // how long you wait. Real keystrokes (pressSequentially()) do fire
  // it, but only cleanly after selectText() (not fill('')) clears the
  // existing value first -- fill('') as a "clear" step suppresses the
  // same trigger fill() always does, even for the real keystrokes that
  // follow it. selectText() doesn't have that effect: it's a genuine
  // selection, not a value write.
  const title = page.getByLabel('Title:');
  await title.selectText();
  await title.pressSequentially(newTitle);
  const description = page.getByLabel('Description:');
  await description.selectText();
  await description.pressSequentially(newDescription);

  // Both fields debounce (`input changed delay:500ms`) before PUTting
  // and swapping their own indicator-box -- assert on the settled
  // success icon (a literal "done" ligature, Node.Title/Description's
  // templatePostSuccess/templatePutSuccess), never the mid-debounce
  // `.loading` spinner the proposal's hazards explicitly warn about.
  await expect(page.locator('label[for="title"] .indicator-box i.material-icons')).toHaveText('done');
  await expect(page.locator('label[for="description"] .indicator-box i.material-icons')).toHaveText('done');

  // Closing the edit view (the check-icon button, revealed once the
  // pencil's own load completes) re-fetches the plain node-detail view
  // from the database -- asserting on it here confirms the edits
  // actually persisted, not just that each indicator claimed success.
  await page.getByRole('button', { name: 'check' }).click();
  await expect(page.locator('#node-detail header h2')).toHaveText(newTitle);
  await expect(page.locator('#node-detail section p')).toHaveText(newDescription);
});
