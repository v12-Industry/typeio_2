import { APIRequestContext, Page, expect } from '@playwright/test';

// Shared setup helpers for this suite's specs -- reused rather than
// duplicated across specs -- reuse the existing Playwright
// setup" call.

export interface CreatedProject {
  id: string;
  title: string;
  description: string;
}

// Drives the add-project UI form end to end and returns the resulting
// project's id (scraped from its rendered card -- ProjectIndex.List's
// `.id` span -- since project creation has no JSON API to read the id
// back from directly). This is the same flow create-project.spec.ts
// exercises as its own test; other specs that just need *a* project to
// exist call this instead of reimplementing it.
export async function createProject(page: Page, titlePrefix: string): Promise<CreatedProject> {
  const title = `${titlePrefix} ${Date.now()}`;
  const description = `Created by e2e/tests/helpers.ts's createProject() at ${new Date().toISOString()}`;

  await page.goto('/ui/projects/vw');
  await page.getByRole('button', { name: 'Create Project' }).click();

  // getByLabel() works because ProjectCreate.View's inputs each carry
  // an `id` matching their <label for="...">.
  await page.getByLabel('Title:').fill(title);
  await page.getByLabel('Description:').fill(description);
  await page.getByRole('button', { name: 'Submit' }).click();

  // Not page.locator('#project-index').filter(...): #project-index is
  // the single list container (one match, so filter() has nothing to
  // narrow among) -- .project-item is the per-card div's class.
  // Scoping by the shared class resolves to every card, then narrows
  // to the one containing this title.
  const card = page.locator('.project-item').filter({ hasText: title });
  await expect(card.getByRole('heading', { name: title, level: 3 })).toBeVisible();

  const id = await card.locator('.id').innerText();
  return { id: id.trim(), title, description };
}

export interface CreatedNode {
  id: string;
  title: string;
  description: string;
  projectId: string;
}

// Adds a node to an existing project via a direct API call
// (Domain.Project.Responder.Api.Node.Post), not through the "Add work"
// panel: this is setup, and driving three interactions and two htmx
// swaps to reach a node every other spec merely needs to exist would
// make each of them a slower, flakier copy of add-work.spec.ts, which
// is the spec that does test that panel. Every spec that needs *a*
// node calls this instead of reimplementing the API-plus-lookup
// dance.
export async function addNode(
  request: APIRequestContext,
  projectId: string,
  titlePrefix: string
): Promise<CreatedNode> {
  const title = `${titlePrefix} ${Date.now()}`;
  const description = `Created by e2e/tests/helpers.ts's addNode() at ${new Date().toISOString()}`;

  const created = await request.post('/api/project/nodes', {
    form: { title, description, projectId },
  });
  if (!created.ok()) {
    throw new Error(`addNode: POST /api/project/nodes failed: ${created.status()} ${await created.text()}`);
  }

  // The POST response above is just "Ok" -- no created-node id -- so
  // fetch it back to find the id. Domain.Project.Responder.Api.Node.Get
  // returns every node in the database, unfiltered by project (
  // filed as a follow-up, not fixed here); the timestamped title is
  // what actually picks out the right one.
  const allNodes = await request.get('/api/project/nodes').then(r => r.json());
  const node = allNodes.find((n: { title: string }) => n.title === title);
  if (!node) {
    throw new Error(`addNode: no node titled ${JSON.stringify(title)} in ${JSON.stringify(allNodes)}`);
  }

  return { id: String(node.nodeId), title, description, projectId };
}

// Creates a project via a direct POST to the same endpoint the
// add-project form submits to
// (Domain.Project.Responder.Ui.ProjectCreate.Submit), bypassing the UI
// form -- same reasoning as addNode() above: this is setup, not the
// thing being tested. project-index-scroll.spec.ts needs enough
// rows to overflow a screen, and driving 30 of them through the real
// form (createProject()) would only add slow, irrelevant setup time.
//
// Returns nothing: the response here is a redirect header for htmx to
// follow (Submit.redirectHeader), not a body with an id to scrape, and
// nothing that needs this helper's projects individually addressable --
// use createProject() instead when a caller needs the id back.
export async function createProjectFast(
  request: APIRequestContext,
  titlePrefix: string
): Promise<void> {
  const title = `${titlePrefix} ${Date.now()}`;
  const description = `Created by e2e/tests/helpers.ts's createProjectFast() at ${new Date().toISOString()}`;

  const created = await request.post('/ui/create-project/submit', {
    form: { title, description },
  });
  if (!created.ok()) {
    throw new Error(
      `createProjectFast: POST /ui/create-project/submit failed: ${created.status()} ${await created.text()}`
    );
  }
}
