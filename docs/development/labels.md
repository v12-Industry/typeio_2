# Issue Labels

Every GitHub issue gets two labels: one `type:*` (what kind of work) and
one `area:*` (what part of the system). This taxonomy was derived from
an actual review of every issue filed in this repo so far, not
picked abstractly — see the mapping below.

An issue that touches visualization code carries a third, one `viz:*`
(which visualization) — see the `viz:*` section below.

## `type:*` — what kind of work

| Label | Meaning |
|---|---|
| `type:bug` | Something isn't working correctly |
| `type:chore` | Maintenance: cleanup, tooling adoption, refactors with no behavior change |
| `type:documentation` | Adding or updating documentation |
| `type:feature` | New capability or behavior |
| `type:spike` | Research/investigation producing a solution-proposal doc, not code |

## `area:*` — what part of the system

| Label | Meaning |
|---|---|
| `area:backend` | Server-side Haskell: routing, containers, environment, config, logging |
| `area:frontend` | Client-side interactivity: htmx, hyperscript — mirrors `docs/development/frontend/` |
| `area:ui` | Lucid-rendered HTML and CSS (`#container`/`#view`, global vs. scoped styles) — mirrors `docs/development/ui/`, deliberately kept separate from `area:frontend` since the docs tree already splits these two |
| `area:testing` | Unit, integration, or E2E test suites and their tooling |
| `area:ci-cd` | GitHub Actions workflows and required checks |
| `area:infrastructure` | Terraform/Terragrunt and other non-application infrastructure |
| `area:tooling` | Dev tooling: formatting, linting, build config |
| `area:process` | How the team/docs/repo operate — not the application itself |

## Conventions

- Every issue gets exactly one `type:*` label. Most get exactly one
  `area:*` label; an issue that genuinely spans more than one area (rare
  — most of this repo's issues have been cleanly single-area) can carry
  more than one. An issue touching visualization code also gets exactly
  one `viz:*` — never more than one, since `viz:all` is how "more than
  one" is spelled.
- `area:ui` and `area:frontend` are intentionally separate, mirroring
  `docs/development/ui/` vs. `docs/development/frontend/` — don't
  collapse them into one "frontend" label just because they're both
  client-facing; they're different concerns (server-rendered markup/CSS
  vs. client-side interactivity).
- `area:testing` covers testing work regardless of *what* is being
  tested — a unit test for a backend module is `area:testing`, not
  `area:backend`, since the interesting fact about that issue is that
  it's testing work, not which module it happens to cover.
- This taxonomy is a snapshot of what this repo's issues have actually
  needed, not a fixed spec — if a new kind of issue doesn't fit either
  dimension well, that's a signal to reconsider the taxonomy the same
  way it was derived (review recent real issues), not to force-fit it or
  invent a label in isolation.
- GitHub's stock `bug`/`documentation`/`enhancement` labels are not used
  from this repo — they overlapped with `type:bug`/`type:documentation`/
  `type:feature` and having both would just be duplicate, confusing
  bookkeeping. The other stock labels (`duplicate`, `good first issue`,
  `help wanted`, `invalid`, `question`, `wontfix`) are untouched — they
  don't overlap with this taxonomy and remain available if needed.

## `run-e2e`

A special-purpose label, outside the `type:*`/`area:*` taxonomy above —
same bucket as the untouched stock labels the Conventions section calls
out (`good first issue`, `question`, etc.), not a `type:*` or `area:*`
label itself.

Opts a PR into `.github/workflows/e2e-test.yml`'s Playwright suite,
which otherwise doesn't run on every PR. It can be applied two ways:

- **On a PR directly** — the PR itself needs E2E coverage (e.g. no
  linked issue, or an already-open PR turns out to need it).
- **On an issue, at creation/triage time** — when the work is expected
  to need E2E coverage as part of its requirements, before any PR
  exists for it. `e2e-test.yml` also reads the labels of any issue a PR
  closes (via GitHub's closing-issue-references), so whichever PR later
  closes that issue picks up the requirement automatically — nobody has
  to remember to also label the PR.

See `docs/development/ci.md`'s "E2E test workflow" section for the full
mechanics.

## `review:approved`

Another special-purpose label outside the `type:*`/`area:*` taxonomy —
same bucket as `run-e2e` above, not a `type:*`/`area:*` label itself.

Applied by the user to a PR they've reviewed and want merged. It's one
of the two merge-authorization signals `CLAUDE.md`'s Git Safety & Branch
Boundaries section accepts before merging any PR is allowed (the other
is `review:pre-approve`, below) — with neither, a PR sits open
regardless of how ready its checks/diff look. Applying it is the user's
call to make, not something to add unprompted or infer from a PR just
having green checks or looking finished.

This one is *after-the-fact*: it says "I have looked at this diff."

## `review:pre-approve`

The issue-side counterpart to `review:approved`, and the other
merge-authorization signal — same special-purpose bucket, not a
`type:*`/`area:*` label.

Applied by the user to an **issue**, ahead of the work: it authorizes
merging whichever PR closes that issue, before that PR exists. On a
pre-approved issue, the Hand-off Rule's "open a PR and stop" doesn't
apply — the PR is opened, required checks are waited on, and then it's
queued for merge — added to this repo's
[merge queue](ci.md#merge-queue) with the `enqueuePullRequest` mutation
in [Queueing from the command line](ci.md#queueing-from-the-command-line),
not `gh pr merge` — without waiting for a separate `review:approved` on
the PR.

The point is latency: for work whose shape the user already agreed to
when filing the ticket, a second round-trip to label the PR adds a wait
without adding review. It's the same authorization, just given earlier.

Boundaries, since it's granted sight-unseen:

- **It covers exactly one PR** — the one that closes that issue, via
  GitHub's closing-issue-references (`Closes #N`), the same linkage
  `run-e2e` uses. It doesn't carry to sibling PRs, follow-ups, or a
  later PR reopening the same ground.
- **It lapses if the PR outgrows the issue.** Pre-approval was granted
  against the ticket's scope; a PR that picked up unrelated changes
  isn't what was approved, so it falls back to needing
  `review:approved` on the PR itself. (Out-of-scope findings should be
  getting their own issue anyway — see `CLAUDE.md`'s Ticket & Branching
  Conventions.)
- **It authorizes the merge, not a shortcut to it.** Required checks
  still have to pass, the change is still verified and still gets its
  tests, and unresolved review feedback on the PR still blocks.
- **It's the user's call to apply**, like `review:approved` — never
  self-applied to an issue, and never inferred from the user sounding
  enthusiastic about the ticket.

## `viz:*` — which visualization

A third dimension alongside `type:*`/`area:*`, and unlike `run-e2e` or
the `review:*` labels it *is* part of the taxonomy: it says which
project visualization an issue applies to.

The app is built to hold several visualizations of the dependency graph
at once and select one by configuration — see
[`../architecture/visualization-switching.md`](../architecture/visualization-switching.md).
They deliberately share no code, so "fix the graph" is not a
well-formed request until you know *which* graph. These labels exist so
that is never ambiguous.

| Label | Means |
|---|---|
| `viz:layered` | The layered orthogonal SVG graph — `graph-rendering.md` |
| `viz:rootless` | The variant that draws the work without the project node |
| `viz:orbital` | The orbital dependency-weighted radial graph, which replicates a shared dependency per work stream — `orbital-dependency-weighted-graph.md` |
| `viz:all` | Spans every visualization: the switching mechanism itself, the shared queries, this taxonomy |
| `viz:tbd` | Visualization work whose target isn't decided yet |

### The rule

**Any issue that touches visualization code carries exactly one `viz:*`
label, applied at issue-creation time** — the same standing requirement
`type:*` and `area:*` already have.

The four cases, so nothing is left to judgement at filing time:

- **One visualization** → that visualization's label.
- **Every visualization** → `viz:all`. Use this for the switching
  machinery, the shared query layer, and changes to this convention —
  not as a shrug when you haven't decided.
- **No visualization at all** → **no `viz:*` label.** CI, release
  process, database schema, logging, the router. Absence of a label
  means "this isn't visualization work", which is why the next case
  needs a label of its own.
- **Undecided** → `viz:tbd`, and it must be resolved to a real
  visualization before the issue is worked. Without this, an unlabelled
  issue would be ambiguous between "not visualization work" and "nobody
  has decided yet", which is exactly the mistake these labels exist to
  prevent.

### Adding a visualization adds its label

A new visualization creates its own `viz:` label as part of the work
that introduces it, and adds a row to the table above. The label set and
the set of visualizations that actually exist are meant to stay in step
— a label with no visualization behind it is as misleading as an issue
with no label.

## `epic:*` — which multi-issue effort

A grouping label, and the only one here that says nothing about *what*
an issue is. It answers "which larger piece of work is this issue part
of", so a sequence spanning many issues can be listed with one query:

```
gh issue list --label epic:orbital
```

| Label | Groups |
|---|---|
| `epic:orbital` | Delivering the orbital dependency-weighted visualization — `../architecture/orbital-dependency-weighted-graph.md` |

It is **orthogonal to `viz:*`**, not a replacement for it. An epic
routinely contains issues with different `viz:*` labels — `epic:orbital`
spans `viz:all` work on the shared seam and the node-identity contract
as well as `viz:orbital` work on the drawing itself, and the two
dimensions answer different questions. Label both.

Most issues belong to no epic and take no `epic:*` label. Reach for one
only when a body of work is genuinely a sequence — several issues, an
order they have to land in, and a design document they all point at.
Two related tickets are just two related tickets.

An epic label is retired when its work is done: the issues keep it as
history, but nothing new gets it, and the row above should say so rather
than leaving a finished effort looking live.

## When to apply labels

Per `CLAUDE.md`'s Ticket & Branching Conventions: apply the appropriate
`type:*` and `area:*` labels at issue-creation time, not as an
afterthought — `gh issue create` accepts `--label` directly. Also apply
one `viz:*` label whenever the issue touches visualization code — see
the `viz:*` section above — and `run-e2e` at issue-creation time when the
work will need E2E coverage, per the `run-e2e` section.

`review:pre-approve` is the user's to apply, at issue-creation or
triage time, on tickets whose outcome they're willing to authorize in
advance. `review:approved` goes on a PR, after review. Neither is ever
applied by an agent.
