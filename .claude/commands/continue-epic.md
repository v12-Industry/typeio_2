---
description: Continue an epic in batch -- catch up on comments for any open PRs, then implement up to N unblocked issues (default 4), one PR each.
argument-hint: <epic-label-suffix, e.g. "manage-project-ux"> [max-issues, default 4]
---

## Resolve the target epic and batch size

Arguments given: `$ARGUMENTS`

- First token: the epic. If given, the target label is `epic:<token>`
  (strip a leading `epic:` first if the user typed the full label
  already, so both `/continue-epic manage-project-ux` and
  `/continue-epic epic:manage-project-ux` work). If no token is given,
  run `gh label list --search "epic:"` to list the epics that actually
  exist in this repo, show them, and ask which one to continue. Don't
  guess.
- Second token, optional: the max number of issues to take on this
  run. Default **4** if not given.

Determine the repo to operate on with
`gh repo view --json nameWithOwner -q .nameWithOwner` rather than
hardcoding one.

## Step 1 -- Catch up on comments for every open PR in this epic

    gh issue list --label "<epic-label>" --state all \
      --json number,title,state,blockedBy,closedByPullRequestsReferences --limit 100

For each issue's `closedByPullRequestsReferences`, confirm state with
`gh pr view <n> --json state` (the list call doesn't return PR state).
For every PR that's still OPEN:

- Check both comment sources -- these are separate APIs, check both:
  `gh pr view <n> --json comments` (top-level) and
  `gh api repos/<owner>/<repo>/pulls/<n>/comments` (inline/file-anchored).
- Address actionable, unresolved feedback: make the changes, push, and
  reply to the specific thread(s) you addressed
  (`-F in_reply_to=<comment_id>` for inline comments).
- Re-run this repo's build/verification step (see its `CLAUDE.md`,
  e.g. `cabal build all`) before pushing if you changed code.
- Never merge, queue, or approve any PR -- only do that if the issue
  or PR explicitly carries this repo's merge-authorization label(s)
  (see its `CLAUDE.md`, e.g. `review:approved` / `review:pre-approve`).

Do this for *every* currently-open PR in the epic, not just one --
this run intentionally allows more than one PR from this epic to be
open at once (see the batch note below), so there may be several to
check.

## Step 2 -- Build the batch

From the same issue list, filter to issues where:

- `state == "OPEN"`,
- every entry in `blockedBy` has `state == "CLOSED"` (an empty
  `blockedBy` list also counts as ready), **and**
- `closedByPullRequestsReferences` has no non-MERGED entry (i.e. this
  issue doesn't already have an open PR from a previous run).

Sort the remaining issues by issue number ascending and take the first
**N** (the max from above). This is the batch. If it's empty, stop --
that's a normal outcome, not an error.

## Step 3 -- Work the batch, one issue at a time

For each issue in the batch, in order, work it exactly per this
repo's own `CLAUDE.md` -- its Ticket & Branching Conventions, Code &
Style Conventions, and Git Safety & Branch Boundaries sections govern
branch naming, commit/PR format, testing, and merge boundaries. In
outline, per issue:

1. `gh issue view <n> --comments` to read the full ticket, including
   comments.
2. Sync the default branch, then branch off it per the repo's naming
   convention. (Branch from the same synced default branch for every
   issue in the batch -- see the note below on why these branches
   don't build on each other.)
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
6. Stop this issue's work once its PR is open -- don't merge, queue,
   or request review beyond opening it, unless the repo's own
   conventions say this specific issue is pre-authorized for that.
7. Move on to the next issue in the batch.

If any single issue in the batch is genuinely blocked (auth/access
broken, an unrelated build failure, or scope that's ambiguous in a way
that matters), leave a comment on that issue explaining why, skip it,
and continue with the rest of the batch rather than aborting the whole
run.

### Why the batch's PRs don't build on each other

Unlike a single-issue run, this mode deliberately does **not** wait for
each PR to merge before starting the next issue -- all issues in the
batch branch from the same synced `main`, so up to N PRs can be open
at once. This trades away collision-avoidance for throughput: if two
issues in the batch touch the same file, each PR will look
individually mergeable against `main`, but merging the second one
after the first has already landed may produce a conflict the user
resolves at merge time. Do not try to prevent this by making later
issues in the batch depend on earlier ones, or by merging as you go --
merging is the user's call per the repo's Git Safety conventions,
never the agent's, regardless of how far into the batch this is.
