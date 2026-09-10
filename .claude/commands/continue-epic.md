---
description: Continue an epic -- handle any in-flight PR's comments first, else implement the next unblocked issue in that epic.
argument-hint: <epic-label-suffix, e.g. "manage-project-ux">
---

## Resolve the target epic

Argument given: `$ARGUMENTS`

- If it's non-empty: the target label is `epic:$ARGUMENTS` (strip a
  leading `epic:` first if the user typed the full label already, so
  both `/continue-epic manage-project-ux` and
  `/continue-epic epic:manage-project-ux` work).
- If it's empty: run `gh label list --search "epic:"` to list the
  epics that actually exist in this repo, show them, and ask which one
  to continue. Don't guess.

Determine the repo to operate on with
`gh repo view --json nameWithOwner -q .nameWithOwner` rather than
hardcoding one.

## Step 1 -- Handle any in-flight PR first

    gh issue list --label "<epic-label>" --state all \
      --json number,title,state,blockedBy,closedByPullRequestsReferences --limit 100

For each issue's `closedByPullRequestsReferences`, confirm state with
`gh pr view <n> --json state` (the list call doesn't return PR state).
If any is OPEN:

- Check both comment sources -- these are separate APIs, check both:
  `gh pr view <n> --json comments` (top-level) and
  `gh api repos/<owner>/<repo>/pulls/<n>/comments` (inline/file-anchored).
- Address actionable, unresolved feedback: make the changes, push, and
  reply to the specific thread(s) you addressed
  (`-F in_reply_to=<comment_id>` for inline comments).
- Re-run this repo's build/verification step (see its `CLAUDE.md`,
  e.g. `cabal build all`) before pushing if you changed code.
- Never merge, queue, or approve the PR -- only do that if the issue
  or PR explicitly carries this repo's merge-authorization label(s)
  (see its `CLAUDE.md`, e.g. `review:approved` / `review:pre-approve`).
- Stop here once handled. Don't start a new issue while one from this
  epic still has an open PR -- one in-flight PR at a time avoids
  collisions between issues that touch overlapping files without a
  formal blocking relationship between them.

If no open PR exists for any issue in this epic, proceed to Step 2.

## Step 2 -- Pick the next ready issue

From the same list, filter to issues where `state == "OPEN"` and every
entry in `blockedBy` has `state == "CLOSED"` (an empty `blockedBy` list
also counts as ready). Among the ready issues, pick the one with the
LOWEST issue number.

If there are no ready issues, stop -- that's a normal outcome, not an
error. Don't open a PR, don't comment, don't create anything.

## Step 3 -- Do the work

If a ready issue was found, work it exactly per this repo's own
`CLAUDE.md` -- its Ticket & Branching Conventions, Code & Style
Conventions, and Git Safety & Branch Boundaries sections govern branch
naming, commit/PR format, testing, and merge boundaries. In outline:

1. `gh issue view <n> --comments` to read the full ticket, including
   comments.
2. Sync the default branch, then branch off it per the repo's naming
   convention.
3. Implement the change and add/update tests per the repo's
   conventions. If the issue references design/reference material
   (e.g. a mockup file), read it for intent, but prefer this repo's
   own existing conventions where they conflict with that material's
   own implementation details.
4. Verify the change builds/tests clean per the repo's documented
   verification step.
5. Commit, push, and open a PR that closes the issue (e.g.
   `Closes #<n>`), labeled to match the issue's own labels plus the
   epic label from this run.
6. Stop once the PR is open. Don't merge, queue, or request review
   beyond opening it, unless the repo's own conventions say this
   specific issue is pre-authorized for that.

If genuinely blocked (auth/access broken, an unrelated build failure,
or scope that's ambiguous in a way that matters), stop and leave a
comment on the issue explaining why, rather than guessing or forcing
it through.
