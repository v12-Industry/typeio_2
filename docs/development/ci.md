# CI

There are six GitHub Actions workflows:

- `.github/workflows/test.yml` — builds the app and runs the unit test
  suite. **Required** to merge into `main`, including a second run
  against every merge-queue entry — see [Merge queue](#merge-queue)
  below.
- `.github/workflows/integration-test.yml` — runs the Docker-backed
  integration test suite. Informational only, not required — see
  [Integration test workflow](#integration-test-workflow) below.
- `.github/workflows/security-scan.yml` — scans dependencies for known
  vulnerabilities with OSV-Scanner. Informational only, not required —
  see [Security scan workflow](#security-scan-workflow) below.
- `.github/workflows/release.yml` — tags and creates a GitHub Release
  once a version bump lands on `main`. Not a check at all (nothing to
  pass or fail against a PR) — see [Release workflow](#release-workflow)
  below.
- `.github/workflows/e2e-test.yml` — runs the Playwright E2E suite
  against a real server, seeded Postgres, and headless browser.
  Informational only, not required, and not run on every PR — see
  [E2E test workflow](#e2e-test-workflow) below.
- `.github/workflows/warm-cache.yml` — populates the cabal build cache
  that `test.yml`'s `pull_request`/`merge_group` runs can't write
  themselves. Not a check at all — see [Cache
  warming](#cache-warming) below.

## What it does

The `test` job runs on **every** pull request into `main` — it is not
path-filtered at the workflow level (see "Why it always runs" below).
Its steps:

1. Check out the PR's code (full history, needed for step 2's diff).
2. Diff against the PR's base branch to check whether anything that
   could affect the build/test result actually changed (`**/*.hs`,
   `*.cabal`, `cabal.project`, or the workflow file itself).
3. **If nothing relevant changed** (e.g. a docs-only PR): every
   remaining step is skipped via `if:`, and the job reports success
   quickly with no GHC/cabal setup at all.
4. **If something relevant did change**: install GHC 9.6.7 / Cabal
   3.12.1.0 via
   [`haskell-actions/setup`](https://github.com/haskell-actions/setup) —
   the same versions used locally (see
   [`onboarding.md`](onboarding.md)/`typeio.cabal`'s `base ^>=4.18.3.0`
   bound) — cache the cabal store and `dist-newstyle` (keyed on
   `typeio.cabal`), then `cabal build all` and `cabal test spec`
   (see [`unit-testing.md`](unit-testing.md)).

No database or service container is involved — `spec` is entirely pure
(see [`unit-testing.md`](unit-testing.md) for what's covered and why).
This step deliberately runs `cabal test spec`, not a bare `cabal test`:
the integration test-suite from
`docs/solution-proposals/integration-testing.md` also exists in
this package now, and has its own CI coverage — see
[Integration test workflow](#integration-test-workflow) below — but a
bare `cabal test` would build and run every test-suite in the package
from *this* job too, silently pulling a Docker-dependent suite into
this required, Docker-less check.

## Merge queue

`main` merges go through a merge queue, not a direct "Merge pull
request" click. Once a PR has an approving state and its own `test` run
has passed, the button reads **"Merge when ready"** instead — clicking
it adds the PR to the queue rather than merging immediately. GitHub then
combines the queued PR with `main`'s current tip (and with any PR
already ahead of it in the queue) into a temporary **merge group** ref,
re-runs `test` against *that*, and only merges for real once it passes.
If it fails, that entry is dropped from the queue (not merged) without
blocking whatever's queued behind it.

**Who may enqueue**: queueing a PR is a merge, so it needs the same
authorization any merge does — `review:approved` on the PR, or
`review:pre-approve` on the issue it closes. See
[`labels.md`](labels.md)'s sections on those two labels, and
`CLAUDE.md`'s Git Safety & Branch Boundaries section. Once a PR is
queued the work is handed to GitHub; there's nothing further to do but
report it, and a dropped entry (its merge-group `test` failed) is a
result to investigate, not to blindly re-queue.

**Why**: without this, `main`'s branch protection needing `test` to
pass "up to date" (`required_status_checks.strict`) meant *any* PR
merging into `main` flipped every other open PR to "out of date,"
forcing a manual branch update + full CI re-run on each one before it
could merge — even for a completely unrelated change. The merge queue
keeps the same guarantee (nothing merges without `test` passing against
what `main` will actually look like right after) but has GitHub do that
update-and-retest step automatically instead of a human doing it by hand
on every open PR each time one merges. Classic branch protection's own
`required_status_checks.strict` is now `false` for exactly this reason —
leaving it `true` would keep the manual "out of date" nag alive
independently of the queue, defeating the point.

**How it's configured**: not through branch protection at all —
GitHub's classic branch-protection API (REST or GraphQL) has no merge
queue field, and confirmed by hitting it directly: the only way to
enable a merge queue is a repository ruleset (`POST
/repos/{owner}/{repo}/rulesets`) with a `merge_queue` rule, paired with
its own `required_status_checks` rule naming `test` (the two rules
travel together — a bare `merge_queue` rule 422s on its own). That
ruleset's `required_status_checks_policy.strict` is deliberately
`false` too, same reasoning as above: the queue's `ALLGREEN` grouping
strategy already re-tests each entry against a fresh `main`, so a
second, independent "must be up to date" gate would just reintroduce
the same friction from a different angle.

**Availability**: merge queue only works on repositories owned by an
**organization** (public repos free, private repos need GitHub
Enterprise Cloud) — not personal-account repos. This repo moved from a
personal account (`jordan-stor-z`) to the `v12-Industry` organization
specifically to unlock this.

**Why `test.yml` needed a new trigger, and nothing else did**: the
queue evaluates required checks against the synthetic merge-group ref,
which fires a `merge_group` event, not `pull_request`. `test` is the
only workflow in `required_status_checks` (both the classic contexts
list and the ruleset's own), so it's the only one that needed
`merge_group:` added to its `on:` — without it, `test` would never run
for a queued entry, GitHub would treat it as permanently missing (not
failing), and nothing would ever clear the queue. `security-scan.yml`
and `e2e-test.yml` aren't required checks, so they don't need it.
`test.yml`'s own base-ref diffing (the "Check for Haskell-relevant
changes" step) and concurrency group both had to account for
`merge_group`'s different event shape too — `github.base_ref` and
`github.event.pull_request.number` are both empty for that event; see
the comments in the workflow file itself for the fallback logic.

**Not yet reflected in `infrastructure/`**: the Terraform/OpenTofu
module (`infrastructure/modules/github-repo`) only wraps
`github_branch_protection` today, not `github_repository_ruleset` — the
merge-queue ruleset was configured by hand via the API, the same way
the original branch protection was before it existed as code (see
[`infrastructure.md`](infrastructure.md)'s "Importing the existing
branch protection"). Whenever that infra is actually applied for the
first time, the import step will need to cover this ruleset too, not
just the branch protection rule.

## Cache warming

`.github/workflows/warm-cache.yml` triggers on `push` to `main` only,
runs the same setup/cache/build steps `test.yml` has (same
`haskell-actions/setup@v2` versions, same `actions/cache@v6` `path`/
`key`, copied exactly rather than re-derived), and stops after `cabal
build all` — no `cabal test`. It exists to populate a cache scope
`test.yml` structurally can't: GitHub Actions cache reads are limited
to a run's current branch or the repo's default branch, and only
certain trigger types (`push`, `workflow_dispatch`,
`repository_dispatch`, `delete`, `registry_package`, `schedule`) are
allowed to *write* into that default-branch scope. `test.yml` only
triggers on `pull_request`/`merge_group`, neither of which qualifies —
so before this workflow existed, no run had ever written a cache into
`main`'s actual scope, and every genuinely new ref (a PR's first push,
or every merge-queue entry on its own synthetic branch) paid a full
cold `cabal build all` regardless of an identical-key cache already
existing elsewhere in the repo.

Every merge lands as a single merge commit (the merge queue's own
`merge_method: MERGE` — see [Merge queue](#merge-queue) above; direct
pushes are blocked entirely), so this workflow's relevance check diffs
`HEAD^...HEAD` — "what changed in the merge that just landed" — the
same "skip GHC setup entirely for a docs-only change" pattern `test.yml`
uses, just against the previous commit instead of a PR's base branch.
No `cabal test` step: anything on `main` already passed that check via
its own PR or merge-queue entry (see "[Why pull requests only, not
`main`](#why-pull-requests-only-not-main)" below) — this workflow exists
purely to leave a cache behind for the *next* run to find, not to
re-verify correctness. Not a required check; nothing waits on it.

See `docs/solution-proposals/ci-cache-warming.md` for
the full diagnosis — confirmed with real run timing and
`actions/cache@v6`'s own log output, not just reasoning — and that proposal for
what landed.

## Integration test workflow

`.github/workflows/integration-test.yml` runs `cabal test integration`
(the suite from `docs/solution-proposals/integration-testing.md` §11
) on every PR into `main` that touches Haskell-relevant files —
following the pattern the solution proposal's §8 had
left open.

A few ways this deliberately differs from the `test` workflow above:

- **A separate workflow file**, not a second job in `test.yml` — keeps
  this suite's different needs (Docker, longer runtime) isolated from
  the required, fast, DB-free `test` job, and makes it trivial to
  promote or demote independently later.
- **Not a required check (yet).** This is a newer, Docker-dependent
  suite; requiring it immediately, on a repo with `enforce_admins: true`
  and therefore no bypass, was judged too much risk before it's proven
  reliable. Once it's been stable for a while, promoting it to required
  is a separate, deliberate branch-protection change — not bundled into
  standing the workflow up.
- **A plain top-level `paths:` filter**, unlike `test.yml`'s
  always-runs-and-skips-internally pattern. That pattern exists
  specifically to protect a *required* check from the "stuck missing
  forever" trap (see [Why it always runs](#why-it-always-runs-and-skips-internally-instead-of-using-paths)
  below) — a trap that only bites required checks. Since this workflow
  isn't required, a docs-only PR simply not triggering it at all is
  fine.
- **No `migrate` CLI setup step.** GitHub-hosted Ubuntu runners already
  have Docker running, and migrations apply themselves from inside the
  disposable container (`test-integration/Integration/Support.hs`'s
  `docker-entrypoint-initdb.d` approach) — nothing extra to install on
  the runner beyond the same GHC/cabal setup `test.yml` already uses.

## Security scan workflow

`.github/workflows/security-scan.yml` runs
[OSV-Scanner](https://github.com/google/osv-scanner) against the repo's
dependencies. It exists to fill one specific gap: Dependabot (native,
free, no workflow needed — see
`docs/solution-proposals/security-scanning.md` §3) doesn't support the
Hackage ecosystem, so nothing else in the repo checks Haskell
dependencies against known CVEs. See the proposal for the full
investigation and decision; this section just documents the shape that
landed.

Steps:

1. Install GHC/cabal via `haskell-actions/setup`, same versions and
   caching as `test.yml`.
2. `cabal freeze`, generating `cabal.project.freeze` at scan time — the
   repo doesn't commit one (deliberately; see the proposal's §5), so
   this is what gives OSV-Scanner exact resolved versions to check
   instead of just the version *bounds* `typeio.cabal` declares.
3. Run `google/osv-scanner-action` recursively from the repo root. This
   picks up the freeze file just generated, and — if/when
   `package-lock.json` is real again — npm dependencies too. One
   tool, one job, both ecosystems.
4. Append the scan's markdown output to the job summary
   (`$GITHUB_STEP_SUMMARY`). This is deliberately the raw scanner action
   with `continue-on-error: true` on the scan step, not this project's
   own reusable workflow (`osv-scanner-reusable.yml`) — that uploads
   SARIF to Security > Code Scanning and fails the job on any finding by
   default, and this check is informational only (below), not a new
   dashboard.

A few ways this deliberately differs from `test.yml` and
`integration-test.yml`:

- **Schedule-only, not a PR check.** It does not run on every PR
  into `main` too (no `paths:` filter — same shape as `test.yml`), to
  catch a newly *introduced* vulnerable dependency at the point it
  landed — see the proposal's §6/§10 for that original decision. Dropped
  A per-PR OSV-Scanner run kept surfacing findings unrelated
  to what a given PR actually changed, on a check nothing could act on
  anyway (informational, next bullet). The weekly `schedule` alone still
  covers what a PR trigger structurally can't — a dependency that didn't
  change but became known-vulnerable since it was last touched — and
  `main` is exactly the right target for that, since it's checking for
  drift in the *outside world* (newly disclosed CVEs), not re-checking
  something a PR already covered. See `docs/solution-proposals/security-scanning.md`'s
  note below its original §6/§10 decision for the follow-up record.
- **Not a required check**, and not planned to become one without a
  separate, deliberate decision — see the proposal's §7 for why a
  vulnerability finding shouldn't block whatever happened to be in
  flight when the scheduled scan ran.
- **A separate workflow file**, not a job in `test.yml` — different
  trigger shape (`schedule` instead of `pull_request`) and different
  blocking semantics (informational vs. required) than `test.yml`'s
  `test` job; see the proposal's §8.

## Release workflow

`.github/workflows/release.yml` watches for a version bump landing on
`main` and, when one does, creates a matching git tag + GitHub Release
with auto-generated notes. See
[`release-management.md`](release-management.md) for the full cutting-a-
release workflow and the rationale behind it (`docs/solution-proposals/release-management.md`
§9 has the original decision); this section just places it among the
other workflows here.

Unlike `test.yml`, `integration-test.yml`, and `e2e-test.yml`, it's not
a PR check at all (`security-scan.yml` isn't either — see
[Security scan workflow](#security-scan-workflow) above — but for a
different reason: it's reacting to schedule drift, not to a version
bump landing):

- **Triggers on `push` to `main`, not `pull_request`.** It isn't
  re-checking anything — `main` only changes via already-checked PRs
  (see [Why pull requests only](#why-pull-requests-only-not-main)
  below) — it's reacting to a version bump that already landed there.
- **Not a required check**, for the same structural reason it isn't a
  check at all: nothing about it can fail a PR.
- Still uses a plain top-level `paths: ['typeio.cabal']` filter, same as
  `integration-test.yml` — safe here for the same reason (not required,
  so nothing gets stuck permanently missing). That's only a cheap
  pre-filter, though: `typeio.cabal` changes for reasons that have
  nothing to do with the version, so the actual check — did the
  `version:` line itself change — happens in the workflow's "Check
  version bump" step.

## E2E test workflow

`.github/workflows/e2e-test.yml` runs the Playwright suite (`e2e/`,
) against a real, compiled `server` process
talking to a real, seeded Postgres, driven by a headless browser. See
`docs/solution-proposals/e2e-testing.md` (decided, §6/§8) for the
full design rationale; this section covers the
CI shape specifically.

Steps, in order:

1. Install GHC/cabal and `cabal build all`, same versions/caching as
   the other workflows.
2. Start a `postgres:15` container via a plain `docker run` step (not
   `services:`, and not `test-integration`'s testcontainers-managed
   approach) — bind-mounting `migrations/` and
   `test-integration/docker/apply-migrations.sh` into
   `docker-entrypoint-initdb.d/`, the same migration mechanism
   `test-integration/Integration/Support.hs` already established. A
   plain step, not a `services:` block, specifically because
   `services:` containers start before the job checks out the repo —
   their bind mounts would see an empty directory, and Postgres only
   runs its `docker-entrypoint-initdb.d` scripts once, at that early
   startup.
3. `cabal run server`, backgrounded (`nohup ... &`, survives the step
   exiting since the process just keeps running on the same runner),
   pointed at that Postgres via the same env vars `.env` sets locally.
4. `POST /api/central/seed-database` once the server's reachable — what
   `make seed-db` already does, reusing the app's own seeding path
   rather than duplicating it.
5. Install Playwright's Chromium (cached on `e2e/package-lock.json`'s
   hash, the same pattern as the cabal-store cache) and `npm test`.

A few ways this deliberately differs from every other workflow here:

- **Three triggers, not one or two**: `workflow_dispatch` (run it right
  now, on demand), a weekly `schedule` (catches drift — something
  breaking with no code change at all, same reasoning
  `security-scan.yml`'s schedule uses, on a different day so the two
  slow/occasional jobs don't contend for runners at the same time), and
  `pull_request` gated on a label.
- **The `run-e2e` label, not "every PR."** This suite is meaningfully
  slower and more moving-parts than the others (browser + server +
  database, versus `test.yml`'s pure in-process run or
  `integration-test.yml`'s single testcontainers-managed database), and
  a finding here isn't necessarily about what a given PR changed — the
  same reasoning `security-scan.yml`'s §7 gives for not blocking a PR on
  an unrelated finding applies just as much to "don't even run this on
  every PR" here.
- **Two jobs, not one, for the `pull_request` case** — a cheap
  `check-e2e-required` job runs first and decides whether the real
  `e2e-test` job (which `needs:` it) should run at all, checking two
  things:
  1. **The PR's own `run-e2e` label** — the direct case: someone
     decides an already-open PR needs E2E coverage and labels it.
  2. **Any issue the PR closes** (`Closes #N` etc. in the PR body —
     GitHub's own "closing issue references") **carrying `run-e2e`** —
     the planning-time case: label an issue `run-e2e` when it's
     created/triaged, as part of recording its requirements, before any
     PR exists for it. Whichever PR later closes that issue picks the
     requirement up automatically, via a GraphQL query
     (`closingIssuesReferences`) `check-e2e-required` makes — a linked
     issue's labels aren't part of the `pull_request` event payload, so
     this can't be a plain `if:` expression the way the PR's own label
     check is; it has to be an actual API call in a step.

  Either path sets `required=true`; `e2e-test`'s own `if:` (checking
  `needs.check-e2e-required.outputs.required`) gates on that. An
  unlabeled PR with no qualifying linked issue costs one cheap job that
  reports quickly — the two-job split keeps that fast precondition
  check separate from ever having to spin up (or skip inside) the full
  GHC+Docker+Postgres+browser job.
- **`check-e2e-required` writes its reasoning to `$GITHUB_STEP_SUMMARY`**
 , not just to the step's stdout log — so "why did/didn't e2e run
  on this PR" is visible at a glance from the PR checks UI's Summary tab,
  covering all three outcomes: required via the PR's own label, required
  via a named closing issue's label (the issue number is named
  explicitly), or not required (naming which closing issues, if any,
  were checked and found unlabeled).
- **Not a required check**, same as `integration-test.yml`/
  `security-scan.yml` — doubly so here, since it isn't even part of
  every PR's checks by default.

**Known race, benign: creating a PR and labeling it `run-e2e` as two
separate, rapid actions**. `opened` and `labeled` are both
trigger types above, so open-then-label fires two `pull_request` events
close together, both landing in `e2e-test.yml`'s own `concurrency`
group (same pattern as the other workflows — see "Same reasoning as
`test.yml`" in the workflow file itself) — the second run's
`cancel-in-progress` cancels the first as designed, but if
the first run's `e2e-test` job had already been dispatched by then, it
can keep running instead of stopping cleanly, leaving a stale
`cancelled` `check-e2e-required` sitting next to a still-running
`e2e-test` from the same (superseded) run. `gh pr checks`/the PR's
checks UI can show a misleading `fail` in that window. Not a workflow
bug — it self-resolves once the still-running job finishes and the
concurrency group frees up for the newer run, or it can be nudged along
with `gh run cancel` on the stale run. Avoid tripping it in the first
place by passing the label at creation time (`gh pr create --label
run-e2e ...`) instead of creating the PR and labeling it in a separate
follow-up call, whenever `run-e2e` is already known to be needed before
the PR exists.

## Why it always runs, and skips internally instead of using `paths`

The first version of this workflow used a top-level `on.pull_request.paths`
filter, so it wouldn't trigger at all for a docs-only PR. That turned out
to be broken the moment `main`'s branch protection was configured to
**require** this check: GitHub has no concept of "this check doesn't
apply to this PR," only "passed" or "missing" — a required check that a
path filter prevents from ever running stays permanently missing, which
blocks the merge forever, with no bypass (`enforce_admins: true` means
even an admin override can't get past it). The fix is the job-level
`if:` pattern above: the workflow (and the check GitHub tracks) always
runs, so it can always report a real result, while the actual expensive
work is still skipped when it isn't needed.

## Why pull requests only, not `main`

Anything that lands on `main` only got there via a PR that already ran
this exact check — re-running it again on `main` itself would just be
repeating a check that already passed, for no new information. So the
workflow triggers on `pull_request` only.

**Worth knowing**: this reasoning depends on nothing landing on `main`
except through a checked PR. That's now actually enforced, not just a
convention — `main` has branch protection requiring a pull request (0
required approvals, so it's about the PR requirement, not review) and
this `test` check to pass, with `enforce_admins: true` (no bypass, for
anyone) — plus, as of the merge queue (see [Merge
queue](#merge-queue) above), a ruleset requiring every merge to
actually go through the queue rather than a direct merge at all. It was
previously just `CLAUDE.md`'s "never push directly to main" rule for
agents, which bound agents but not humans or GitHub itself — see the
note above about what configuring this actually required from the
workflow.

`integration-test.yml` triggers on `pull_request` only too, for the
same reason — it's just not part of what branch protection enforces.

`security-scan.yml`, `release.yml`, and `warm-cache.yml` are the three
workflows that don't trigger on `pull_request` at all, for three
different reasons: `release.yml` triggers on `push` to `main` instead —
see [Release workflow](#release-workflow) above — because it isn't
re-checking a PR, it's reacting to one that already merged.
`security-scan.yml` triggers on a weekly `schedule` only —
see [Security scan workflow](#security-scan-workflow) above — because a
per-PR run was checking something a PR trigger can't meaningfully check
(whether a dependency became known-vulnerable with no code change at
all); `main` is the right target for that scheduled run for the same
"already checked, nothing new to say" reason `pull_request`-only is
right for the others. `warm-cache.yml` also triggers on `push` to
`main`, but for close to the opposite reason `release.yml` does: not
because re-checking correctness on `main` would be redundant, but
because `main` is the *only* place GitHub allows writing the cache
scope this workflow exists to populate — see [Cache
warming](#cache-warming) above.

`e2e-test.yml` goes further still: its `pull_request` trigger is gated
on the `run-e2e` label rather than running unconditionally, on top of
its own weekly `schedule` and an on-demand `workflow_dispatch` — see
[E2E test workflow](#e2e-test-workflow) above.

## Running the same checks locally

Before CI existed, running `cabal test`/`make test` locally before
pushing was part of the standard workflow. It no longer has to be — the
PR itself is the enforcement point now — but it's still the fastest way
to find a failure before waiting on a CI run:

```
cabal build all
cabal test spec   # or: make test
```

This is the unit suite only, matching the required `test` job. The
integration suite is separate:

```
cabal test integration   # or: make test-integration
```

It needs Docker locally (see [Integration test workflow](#integration-test-workflow)
above for what it runs in CI — informational only, not required). See
[`integration-testing.md`](integration-testing.md) for the full
write-up of how the suite works and what it covers.

The E2E suite is separate again, and doesn't have a single `cabal`
command — it needs a real running server and database, not just
Docker. See [`e2e-testing.md`](e2e-testing.md) for the full write-up
(where specs live, how to run them, what's covered, and the
Playwright/htmx interaction hazards found so far) — `e2e/README.md`
covers the same local sequence as a quick-start pointer.

**Running tests locally is now optional; writing/updating them is not.**
CI catching a missing or broken test after the fact is not a substitute
for adding or updating tests as part of the change that needs them —
see `CLAUDE.md`'s Code & Style Conventions.
