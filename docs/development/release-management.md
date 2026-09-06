# Release Management

How a release actually gets cut, as currently built. For the full
comparison of options and the reasoning behind each choice below, see
[`../solution-proposals/release-management.md`](../solution-proposals/release-management.md)
(§9 has the final decision this doc restates as current fact) — this
doc only describes what landed, not the tradeoffs, and doesn't
re-litigate them.

## Cutting a release

There's exactly one manual step: open a normal PR that bumps
`typeio.cabal`'s `version:` field (semver — `MAJOR.MINOR.PATCH`).
Deciding what kind of bump a change warrants is the one real judgment
call in this process, deliberately not automated — see the proposal's
§3 for why. The PR can be version-only, or paired with the change that
motivated the bump.

## What happens automatically once that PR merges to `main`

`.github/workflows/release.yml` triggers on `push` to `main` and
compares `typeio.cabal`'s `version:` line before and after the push. If
it changed:

1. Creates and pushes a git tag, `vX.Y.Z` (e.g. `v0.2.0`), read straight
   out of the new `version:` value.
2. Runs `gh release create vX.Y.Z --generate-notes` — a GitHub Release
   whose notes are auto-generated from merged PR titles since the
   previous tag.

If `version:` didn't change (`typeio.cabal` can be edited for other
reasons — a new dependency bound, a new module, etc.), the workflow is a
no-op. It is **not** a required status check — it doesn't gate merging,
it reacts to a version bump that already landed (same "why pull
requests only" reasoning [`ci.md`](ci.md) gives for `test.yml`, applied
here to explain why this workflow runs on `push` instead: nothing about
a version bump landing on `main` needs re-checking).

No further manual steps — no hand-run `git tag`, no hand-run `gh
release create`.

## What deliberately doesn't exist here, and why

- **No `CHANGELOG.md`.** GitHub's auto-generated release notes
  (above) are the source of "what changed" — a hand-maintained
  changelog would be a second, redundant place recording the same
  information, with a real risk of drifting out of sync.
- **No GitHub Milestones.** Not adopted — at this project's size (a
  handful of dozens of issues, one maintainer, per the proposal's §2),
  there's no backlog/coordination problem for Milestones to solve.
  Revisit if issue volume or contributor count grows enough that "what's
  going into the next release" stops being obvious from the tracker
  alone.
- **No release branches.** Tags are created directly off `main` — see
  "Branch strategy" below.

## Branch strategy: none beyond what already exists

Releases are tagged directly off `main`; there's no `release/x.y` branch
or equivalent. `main` is already required to be shippable at every
commit (branch protection + the required `test` check, see
[`ci.md`](ci.md)), and this is a pre-1.0 project with no external
consumers who've ever pinned to a released version — a release branch's
whole purpose (patching an already-shipped version while `main` has
moved on) has no problem to solve yet. Revisit if/when this genuinely
ships to external users who pin versions and a real need to patch an
older release independently of `main` shows up — not before.

## Tag format

`vX.Y.Z` — the conventional prefix GitHub's own tooling and `gh
release` expect by default (e.g. `v0.2.0` for `version: 0.2.0`).
