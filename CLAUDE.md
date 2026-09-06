# CLAUDE.md — Project Guide & Rules

## Project Overview

A Haskell web application, backed by PostgreSQL, for tracking project
tasks ("nodes") and the dependencies between them. The UI presents a
graph-based layout for visualizing and managing those dependencies.

## Tech Stack & Architecture

- **Language & Runtime:** Haskell, built with `cabal` (GHC via `ghcup`).
- **Web layer:** no external framework (no Scotty/Servant/Yesod) — a
  hand-rolled stack on WAI/Warp:
  - Routing: a custom tree-based router (`Platform.Web.Router`, built on
    `Data.HashTree` combinators), not string-pattern matching.
  - Dependency wiring: a `Container` pattern (`Container.Root`,
    `Container.Build`) — root → per-domain → API/UI sub-containers, each
    holding just the dependencies its handlers need. This project's form
    of DI; no typeclass-based effects system.
  - Middleware: an ordered pipeline in `Platform.Web.Middleware`
    (request-id tagging, request/response logging, index rendering,
    static file serving) — order matters, it's composed via `foldr1 (.)`.
  - Logging: structured JSON via `Logging.Core` (`fast-logger`), with two
    consumers — DB query logging (`Logging.Database`) and HTTP
    request/response logging (`Domain.System.Middleware.Logging.*`),
    correlated by a per-request UUID.
  - Full write-up: [`docs/development/backend/`](docs/development/backend/)
    (one file each for routing, environment, containers, logging).
- **HTML rendering:** Lucid — UI is built as Haskell combinators
  (`Html ()` values, e.g. `div_`, `header_`) evaluated server-side to
  HTML. There are no template files; a `View.hs`/template module per
  feature is the pattern (see `responder/ui/*/View.hs`). Full write-up:
  [`docs/development/ui/`](docs/development/ui/).
- **Client-side:** htmx (partial-page swaps between a persistent
  `#container` shell and per-page `#view` fragments), hyperscript.org
  (the `h_ "..."` attribute, for small declarative effects like
  flash-on-update), and `graph-viewport.js` (pan/zoom over the
  dependency graph, driven by a vendored `d3-zoom` — the graph itself
  is laid out server-side in Haskell and arrives as finished SVG, so
  there is still no client-side layout code and no graph data sent to
  the browser; d3 only moves a transform, and loads only on the graph,
  never app-wide). Full write-up:
  [`docs/development/frontend/`](docs/development/frontend/).
- **Database:** PostgreSQL 15 (Docker), accessed via esqueleto/persistent.
- **Migrations:** SQL files in `migrations/`, managed via the `migrate`
  CLI, paired `.up.sql`/`.down.sql`.

## Docs Map

The bullets above are a fast-orientation summary, not the full picture —
`docs/` has the actual depth (rationale, gotchas, code examples). Start
at [`docs/README.md`](docs/README.md) for the full index; the common
cases:

| Need to know about... | Read |
|---|---|
| Getting set up / how a request flows end-to-end | `docs/development/onboarding.md` |
| `#container`/`#view`, Lucid rendering, CSS conventions | `docs/development/ui/` |
| htmx or hyperscript attribute patterns | `docs/development/frontend/` |
| The router, `Env`, containers (DI), or logging | `docs/development/backend/` (one file each) |
| The `project` DB schema: entities, columns, relationships, ER diagram | `docs/development/backend/database-schema.md` |
| CI: what it runs, when, and how to reproduce it locally | `docs/development/ci.md` |
| Dependabot / security scanning: what runs, where findings show up, how to triage | `docs/development/dependency-security.md` |
| Running/writing unit tests, and what's out of scope (responders) | `docs/development/unit-testing.md` |
| Running/writing integration tests (the responder-testing answer) | `docs/development/integration-testing.md` |
| Running/writing E2E tests (Playwright, htmx interaction hazards, CI's `run-e2e` label) | `docs/development/e2e-testing.md` |
| Anything touching the dependency graph's layout or rendering | `docs/architecture/graph-rendering.md` -- the pipeline for the *layered* visualization: module map, per-phase contracts, and the dependency-vs-containment distinction |
| How the app holds several graph visualizations and picks one, and what they may share | `docs/architecture/visualization-switching.md` -- the request parameter, the dispatch table, and what visualizations share |
| The orbital dependency-weighted visualization -- radial, with shared dependencies replicated per work stream | `docs/architecture/orbital-dependency-weighted-graph.md` -- the design, its unfolding and placement contracts, and its DOM contract |
| What a given visualization actually draws, and where its own code lives | `docs/development/visualizations/` -- one file each for Layered, Rootless and Orbital |
| Which GitHub issue labels to use | `docs/development/labels.md` |
| How to cut a release (version bump, tagging, GitHub Releases) | `docs/development/release-management.md` |
| Repo-level config (GitHub branch protection) as OpenTofu/Terragrunt | `docs/development/infrastructure.md` |
| Why something was decided a certain way, or was rejected | `docs/solution-proposals/` — check its `Status` line first |

If you're about to touch code in one of these areas and haven't read its
doc yet, read it first — that's the point of it existing.

**Three doc directories, three different jobs:** for "how do I build X"
or "how does X work," check `docs/development/` first — it describes how
the app *actually, currently* works, and is the primary reference for
development decisions. If something isn't reflected there, it either
isn't built yet or isn't true. `docs/architecture/` is for "how is this
designed, and what must I not break" — module structure, contracts and
invariants; unlike `development/`, a doc there may describe a design
that is only partly built, so **read its status markers before treating
any section as current behavior** (`docs/architecture/README.md` has the
full distinction). `docs/solution-proposals/` is
for "why was X decided this way" — a point-in-time investigation and
decision record, not a live source of truth. A proposal's existence,
even one with a confident "Decision" section, does **not** mean it was
implemented. Always check the doc's own `Status` line, and cross-check
against `docs/development/` for whether it actually happened, before
treating a proposal as current guidance.

## Setup & Local Development

- **Build:** `cabal build all`
- **Run the server:** `cabal run server` (loads config from `.env` — see
  that file for the required variables; none are hardcoded).
  ⚠️ **There is no environment variable for the graph visualization.**
  Which dependency-graph visualization renders is chosen per request by
  an optional `visualizationMode` query parameter (`Layered`,
  `Rootless` or `Orbital`); an absent one takes a hardcoded default, an
  unrecognised one is a validation error. If an old `.env` still has a
  `GRAPH_VISUALIZATION` line, delete it — nothing reads it. See
  [`docs/architecture/visualization-switching.md`](docs/architecture/visualization-switching.md).
- **Start Postgres:** `make run-postgres`
- **Migrations:** `make migrate-up` / `make migrate-down` /
  `make migrate-down-all` / `make migrate-new NAME=<name>` /
  `make migrate-version` / `make migrate-force VERSION=<v>`
- **Seed the database:** `make seed-db`
- **Verifying a change:** `cabal build all` (compiles clean, `-Wall` is
  on). A unit test suite exists (`cabal test spec` / `make test`) and CI
  runs it on every PR into `main` (GitHub Actions,
  `.github/workflows/test.yml` — see
  [`docs/development/ci.md`](docs/development/ci.md)), so running it
  locally before pushing is no longer required — the PR is the
  enforcement point. A separate integration test suite also exists
  (`cabal test integration` / `make test-integration`, needs Docker
  locally) and runs on every PR via a second workflow,
  `.github/workflows/integration-test.yml` — informational only, not
  yet a required check (see `docs/development/ci.md`). See
  [`docs/development/integration-testing.md`](docs/development/integration-testing.md)
  for how to run it and what it covers, and
  `docs/solution-proposals/integration-testing.md` for the rationale
  behind each design choice.
  **Use the scoped `cabal test spec`/`cabal test integration` (or their
  `make` targets), not a bare `cabal test`** — the latter runs every
  test-suite in the package, including the Docker-dependent one. Run
  relevant `make migrate-*` commands for migration changes.
- ⚠️ **`make test-migrations` is currently broken** — it calls
  `./scripts/test-migrations.sh`, which does not exist anywhere in the
  repo. Don't rely on it; use `cabal build all` instead until it's fixed.

## Database Schema (`project`)

Full reference, with an ER diagram:
[`docs/development/backend/database-schema.md`](docs/development/backend/database-schema.md).
Quick summary:

- `project.project`: Core project container.
- `project.node`: Project nodes/tasks — JSONB attributes, description,
  title, timestamps, references to project/status/type.
- `project.node_type` / `project.node_status`: Valid node categories and
  status states.
- `project.node_status_change`: Audit trail of node status transitions.
- `project.dependency`: Graph edges, `node_id` → `to_node_id`.
- `project.project_vw`: View of root project nodes with a `last_updated`
  aggregate.

## Code & Style Conventions

- Explicit type signatures, clear module exports.
- **Do not add comments to library source code.** Nothing under
  `lib/src` gets a comment — not explanatory prose, not a Haddock
  module header, not a `-- ^` on a record field, not a one-line note
  above a tricky expression. Name things well and let the code read as
  itself; if a passage needs a paragraph to be understood, that is a
  signal to restructure it, not to annotate it.
  - **The only exception is test files**, where a *brief* comment
    explaining what a non-obvious case is pinning is welcome. Keep those
    short — a sentence or two, not an essay.
  - This applies to code an agent writes as much as to code a human
    writes, and it applies when *editing* an existing file too: don't
    reintroduce commentary alongside a change.
  - Language pragmas (`{-# LANGUAGE ... #-}`) are not comments and stay.
- **Documentation describes the application as it is today.** Not how it
  got here. Do not write issue numbers, past decisions, or evolution
  narratives into `docs/development/`, `docs/architecture/` or this
  file — no "this used to", no "changed in #N", no "before X the app
  did Y", no status markers recording when something was built. A
  reader should be able to learn what the app does without the issue
  tracker open, and without being told about states it is no longer in.
  - **Keep the rule, drop the story.** A constraint that exists because
    something once went wrong is still a constraint: state it in the
    present tense as a fact about the code. "The arrowhead sits on the
    dependent" stays; "this section previously asserted the opposite,
    and it cost eight issues" does not.
  - **The exception is `docs/solution-proposals/`**, which are
    deliberately point-in-time records of a decision at the moment it
    was taken. Their issue references and rejected alternatives are the
    content, and they are left alone.
  - History that is genuinely worth keeping belongs in a solution
    proposal or in the git log, not scattered through reference docs.
- Responder modules are one file per HTTP verb under
  `responder/api/<Domain>/<Verb>.hs` (e.g. `Get.hs`, `Post.hs`), and one
  `View.hs`/template module per feature under `responder/ui/<Feature>/`.
- SQL migrations: always paired `.up.sql`/`.down.sql`, sequential
  numbering.
- Never hardcode DB credentials or web ports — pull config from `.env`
  via `Config.App`/`Config.Db`/`Config.Web`.
- **Tests are expected alongside the code they cover** — currently pure,
  dependency-free modules (`Common.Validation`, `Data.*`, `Config.*`;
  see `docs/development/unit-testing.md` for what's in/out of scope and
  why). CI running the suite on a PR (see Setup section) is a
  check that tests exist and pass, not a substitute for writing them —
  don't skip adding/updating a test for a change because CI will "catch
  it anyway."
- **Formatting is automated via Fourmolu** (`fourmolu.yaml` at the repo
  root) — see `docs/solution-proposals/haskell-auto-formatting.md` for
  the rationale. Don't hand-align `=` or import columns. `make format`
  formats every `.hs` file in place; `make format-check` checks without
  modifying anything (non-zero exit on a diff) — the same command
  CI/pre-commit would run. For a human editor, point HLS's
  `formattingProvider` setting at `fourmolu` (`.vscode/settings.json`
  already does this for VS Code; other editors need the equivalent
  setting) and it formats on save. For an AI agent (Claude Code), a
  `PostToolUse` hook in `.claude/settings.json` runs
  `fourmolu --mode inplace` on every `Write`/`Edit` to a `.hs` file
  automatically — no need to ask for formatting.

## Ticket & Branching Conventions

- Tickets are tracked as **GitHub Issues** — use `gh issue list` /
  `gh issue view <n>`, not a local file.
- **When creating an issue**, apply one `type:*` and one `area:*` label
  per [`docs/development/labels.md`](docs/development/labels.md) —
  `gh issue create` takes `--label` directly. Not optional/an
  afterthought; do it at creation time.
- **Also apply one `viz:*` label if the issue touches visualization
  code** — which project visualization it is for. The graph has more
  than one visualization by design and they share no code, so "fix the
  graph" is not a well-formed ticket until it says *which* graph.
  `viz:all` is for work spanning every visualization (the switching
  mechanism, the shared queries); `viz:tbd` is for visualization work
  whose target isn't decided yet, and must be resolved before the issue
  is worked. An issue touching no visualization gets **no** `viz:*`
  label — that absence is meaningful, which is why `viz:tbd` exists. See
  [`labels.md`](docs/development/labels.md)'s `viz:*` section for the
  label set, and
  [`docs/architecture/visualization-switching.md`](docs/architecture/visualization-switching.md)
  for what a visualization is.
- **Also apply `run-e2e` at issue-creation time when the work will need
  E2E coverage** — i.e. its acceptance criteria involve a user-facing
  flow through the UI (the kind of thing `e2e/` tests drive a browser
  against), not backend-only or docs-only work with nothing for a
  browser-driven test to exercise. Labeling the *issue* (not just, or
  instead of, the PR that eventually closes it) records "needs E2E
  coverage" as part of its requirements up front, and
  `.github/workflows/e2e-test.yml` picks it up automatically on
  whichever PR later closes it (via GitHub's closing-issue-references),
  without anyone needing to remember to also label that PR — see
  [`docs/development/ci.md`](docs/development/ci.md)'s "E2E test
  workflow" section for the full mechanics. If it's unclear at
  creation time, skip it — a PR can still be labeled directly later.
- **File a new issue for an out-of-scope finding, rather than fixing it
  inline or silently dropping it.** When work on one issue surfaces a
  distinct problem outside that issue's scope (a bug, inconsistency,
  stale doc, missing test, etc.), open a new GitHub issue for it with the
  correct `type:*`/`area:*` labels (per
  [`docs/development/labels.md`](docs/development/labels.md)) instead of
  folding an unrelated fix into the current PR (scope creep) or just
  letting the finding evaporate because it was only ever mentioned in
  conversation.
  - **Before filing, check for an existing issue** —
    `gh issue list --search "<keywords>"` (try a couple of related-term
    variants too, since exact wording won't always match) across *both*
    open and closed issues — to avoid duplicate bookkeeping. Only file if
    nothing already covers it.
  - This is about *out-of-scope* findings specifically. A small fix
    squarely inside the current PR's own diff (e.g. a typo on a line
    already being touched) is still fine to just fix inline.
- Branch naming: `feature/issue-$N-<short-description>` for issue `$N`.
- Workflow:
  1. `gh issue view <n> --comments` to read the ticket — **`--comments`
     matters**: plain `gh issue view <n>` only shows a comment *count*,
     not their content, so a heads-up left on a ticket (e.g. a snag
     found implementing a related issue) is silently invisible without
     the flag.
  2. Confirm a clean workspace (`git status`), then
     `git checkout main && git pull`.
  3. `git checkout -b feature/issue-$N-<short-description>`.
  4. Implement the change, adding/updating tests for it (see Code &
     Style Conventions).
  5. Verify with `cabal build all` (and migration commands if relevant).
     Running `cabal test spec`/`make test` locally is optional — CI runs
     it on the PR — but it's the fastest way to find a failure early.
  6. Commit referencing the issue, push, and open a PR with
     `gh pr create` — include `Closes #$N` in the body when the PR fully
     resolves the ticket. **If the PR needs `run-e2e` and that's already
     known** (the issue didn't already carry it), pass `--label run-e2e`
     directly on `gh pr create` rather than labeling it in a separate
     follow-up call — creating a PR and labeling it right after fires
     two `pull_request` events (`opened`, then `labeled`) close
     together, which races `e2e-test.yml`'s own `concurrency`
     cancellation (harmless, but produces a confusing transient `fail`
     — see `docs/development/ci.md`'s "E2E test workflow" section).
  7. **If the issue carries `review:pre-approve`, don't stop at the
     PR** — that label is advance merge authorization for this PR, so
     wait for required checks and queue it for merge yourself. See the
     Git Safety & Branch Boundaries section below for the exact
     conditions and commands.
  8. If the ticket auto-closed from an earlier merge, add a closing
     comment linking the PR instead of re-closing it.
- **PR comments come from two separate GitHub APIs — check both, every
  time, or you will miss feedback.** `gh pr view <n> --json comments`
  only returns top-level conversation comments. Inline/file-anchored
  review comments (left on a specific line in the GitHub UI's "Files
  changed" tab) do **not** show up there — they need
  `gh api repos/<owner>/<repo>/pulls/<n>/comments`. When asked to check
  a PR for feedback, run both before concluding there's nothing to
  address. To reply to an inline comment specifically (not just leave a
  new top-level comment), use
  `gh api repos/<owner>/<repo>/pulls/<n>/comments -f body="..." -F in_reply_to=<comment_id>`,
  with the `id` from the inline-comments listing above.

## Git Safety & Branch Boundaries (STRICT)

- **A feature branch may pull `main` in *onto itself*** — via
  `git rebase origin/main` or `git merge origin/main` run on that
  feature branch, force-pushing only to that branch's own remote (never
  to `main`) — to resolve a merge conflict blocking mergeability/CI, or
  to pick up upstream changes. This is about keeping a feature branch
  current, not landing it; only do this to the branch you're actively
  working on this session, not an arbitrary other branch.
- **Merge a PR only with the user's explicit authorization, which comes
  as one of exactly two labels** — `review:approved` on the PR, or
  `review:pre-approve` on the issue that PR closes. Both are the user's
  call to apply, never something to add unprompted or infer from
  context (green checks and a finished-looking diff are not
  authorization). With neither: never merge a feature branch *into*
  `main` and never merge a PR — no `gh pr merge`, no adding it to the
  merge queue, no fast-forwarding/merging a branch's work onto `main`
  by any other means. See [`labels.md`](docs/development/labels.md)'s
  `review:approved` and `review:pre-approve` sections.
  - **`review:approved` (on a PR)** — after-the-fact: the user has
    reviewed *that diff* and wants it merged.
  - **`review:pre-approve` (on an issue)** — ahead-of-time: the user
    authorizes merging whichever PR closes that issue, before the PR
    exists. Seeing it on the issue you're working, you are cleared to
    queue that PR for merge yourself once the conditions below are met;
    don't wait for a separate `review:approved` on the PR, and don't
    ask. It authorizes **only** the PR that closes that issue, and only
    while that PR stays within the issue's scope — if the work grew
    beyond the ticket, it's no longer pre-approved, so stop at the
    hand-off and wait for `review:approved` on the PR itself. It is
    also not a licence to skip anything else: the change is still
    verified (`cabal build all`), still gets its tests, and out-of-scope
    findings still get their own issue rather than being folded in.
  - **How to merge, under either label:** rebase the branch onto
    current `main` first if it's behind (the same pull-in-onto-itself
    mechanism above), push, wait for required checks to pass, then add
    the PR to `main`'s **merge queue**:

    ```bash
    PRID=$(gh pr view <n> --json id --jq .id)
    gh api graphql -f query='
      mutation($id: ID!) {
        enqueuePullRequest(input: {pullRequestId: $id}) {
          mergeQueueEntry { position state }
        }
      }' -f id="$PRID"
    ```

    **`gh pr merge` does not work here** — it routes through
    auto-merge, which is disabled on this repository, so it fails on
    any PR whatever its state. **`gh pr merge --admin` is not the
    fallback either**: it bypasses the queue and branch protection
    instead of joining the queue. The mutation above is the only
    correct path.

    GitHub then re-runs `test` against the merge group and lands the
    PR from there, as a merge commit. A `state` of `QUEUED` means the
    "queue for merge" step is done: don't sit on the queue. If the
    entry gets dropped (its merge-group `test` failed), report that
    rather than blindly re-queueing. See
    [`ci.md`](docs/development/ci.md)'s "Merge queue" section.
- **NEVER check out `main` to edit it directly.** Only check it out to
  sync (`git checkout main && git pull`) before branching.
- **NEVER push directly to `main` or `master`.**
- **Hand-off Rule:** once a feature branch is pushed and verified
  (`cabal build all`, plus migration checks if relevant), open a PR and
  stop — merging is left to the user, unless/until they apply
  `review:approved` to it (see above). **The one exception is a PR
  closing an issue already labeled `review:pre-approve`** — there the
  authorization arrived before the PR did, so instead of stopping you
  wait for required checks and queue it for merge, then report that it's
  queued.

## Known Gotchas

- **`make test-migrations` is broken** — see Setup section above.
- **A solution-proposal's "Decision" section isn't proof it was built.**
  A proposal can carry a confident write-up and a "Decided" status for
  something that was never implemented, or that was later decided
  against. Check its `Status` line and cross-check `docs/development/`
  before treating one as current guidance.
- **`lib/src` mirrors the module tree byte-for-byte, casing included.**
  A directory whose case doesn't match its module path works fine on
  macOS's case-insensitive filesystem and fails outright on CI's Linux
  runner, where GHC reports `Cabal-7554: can't find source for
  Platform/Web in lib/src`. A mismatch can also live in the **git
  index** while `ls` shows the right thing, which a filesystem walk
  cannot detect on a case-preserving filesystem.
- **Renaming for case alone needs two steps.** `git mv old New` fails
  on macOS with "Invalid argument"; use
  `git mv old old_tmp && git mv old_tmp New`.
