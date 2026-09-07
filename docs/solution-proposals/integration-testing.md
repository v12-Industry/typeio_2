# Solution Proposal: Integration Testing

- **Status:** Decided — see §11. Implementation tracked in #65 (pilot)
  and #66–#69 (remaining responders).
- **Date:** 2026-08-30
- **Related:** #42 (this spike), the deferred responder-testing question
  from `docs/solution-proposals/unit-testing.md` §8 Decision, #17
  (E2E spike — cross-referenced below on the shared ephemeral-database
  question), #41 (unit tests in CI — cross-referenced on the CI
  database gap it deliberately left open)

## 1. Problem statement

The unit-testing decision explicitly excluded responders (WAI handlers
that touch the database directly) from unit testing, to preserve
Locality of Behavior, and named integration tests against a real
database as the eventual answer for that layer. This is that eventual
answer — but it has enough genuinely open design questions that it
needs to be worked out before there's a ticket to "just build."

## 2. Terminology check

The working description was "mock database." That's not quite it: a
mock/stub database would mean faking persistent/esqueleto's query layer
itself (fake Postgres protocol responses, or swapping the whole
`ConnectionPool`-and-query machinery for something in-memory) — high
effort, and it would stop testing anything real about how the app talks
to actual Postgres (constraints, joins, transaction behavior). What's
actually wanted — seed known data, exercise a real responder, assert the
database ended up correct — needs a **real, disposable Postgres
instance**, not a mock. Using precise language matters here so a future
ticket doesn't go build the wrong thing.

## 3. What are we targeting?

Not "every responder." Following the same narrow-first pattern as #28
(which covered test infrastructure + exactly one module, with the rest
tracked as follow-ups in #29–#34): pick one representative flow as the
pilot.

**Recommended pilot: `Domain.Project.Responder.Api.Node.Post.handlePostNode`.**
It's a strong candidate specifically *because* of how much it depends on
real database state:

- Requires an existing `Project` row.
- Requires `NodeStatus`/`NodeType` lookup rows (`"active"`, `"work"`,
  `"project_root"`) to already exist.
- Requires an existing root `Node` for that project, to attach the new
  node's `Dependency` edge to.
- On success, inserts both a `Node` and a `Dependency` row.

That's a real, multi-table, foreign-key-and-join-driven flow across
`Project`, `NodeStatus`, `NodeType`, `Node`, and `Dependency` — exactly
the kind of thing a pure/hand-built-fake-repo unit test (the option
rejected in the unit-testing decision) can't meaningfully exercise, and
exactly what integration testing is for. The rest of the write/mutate
handlers (`Node/Description`, `Node/Status`, `Node/Title`, etc.) would
follow in their own tickets once this pilot proves out the approach.

## 4. The database itself

Options for getting a migrated, disposable Postgres for a test run to
talk to:

| Option | How it works | Fit |
|---|---|---|
| [`testcontainers`](https://github.com/testcontainers/testcontainers-hs) + [`testcontainers-postgresql`](https://hackage.haskell.org/package/testcontainers-postgresql) | Docker-managed Postgres container, started and torn down by the test process itself | **Recommended.** Self-contained — no manual "start Postgres first" step, works identically locally and in CI (GitHub Actions runners have Docker available), and the Postgres version is pinned the same way `local/script/start-postgres.sh` already pins `postgres:15`. |
| [`ephemeral-pg`](https://hackage.haskell.org/package/ephemeral-pg) | Spins up a throwaway Postgres cluster directly via `initdb`, no Docker | Possibly faster (no container overhead), but less proven for this project — worth a quick trial if `testcontainers` setup friction becomes a real problem, not the starting point. |
| Reuse `local/script/start-postgres.sh` | The same Docker container dev already uses, pointed at a separate test database/schema | Zero new dependency, but requires a human (or a CI step) to have already run `make run-postgres` before tests — not self-contained the way the other two are. Weaker fit for "just run `cabal test`." |

**Recommendation: `testcontainers` + `testcontainers-postgresql`.**

## 5. Test isolation between tests — a real constraint, not just a preference

The obvious-sounding answer is "wrap each test in a transaction, roll it
back at the end." **That doesn't work as-is with how this codebase's
responders run queries.** Every responder calls `runSqlPool` internally
(e.g. `handlePostNode`'s `flip runSqlPool pl . runEitherT $ ...`), and
`runSqlPool` commits its own transaction on completion — there's no way
for a test to wrap that in an outer transaction and roll it back
afterward without changing how the handler itself runs its queries,
which is out of scope (that's the repository-injection refactor the
unit-testing decision already rejected, for the same Locality-of-Behavior
reason).

**Recommendation: truncate the relevant tables between tests instead.**
Simpler, compatible with responders exactly as they're written today,
and fast enough for a Postgres instance that's already running (the
container start/stop cost, not per-test truncation, will dominate
runtime). Re-migrating per test run (not per test) is still worth doing
once, at suite startup, against the fresh container.

**Settled, not pending**: this section previously noted a dependency on
[#50](https://github.com/v12-Industry/typeio_2/issues/50), which
explored lifting the transaction boundary out of the responder
specifically to get cross-domain atomicity. #50 was **decided against**
— not because the "`runSqlPool` always commits" reasoning above was
wrong, but because cross-domain atomicity doesn't actually require
lifting the transaction at all: `Domain.Central` already exists as
where multiple domains compose to serve one view, and the standing
model is one responder calling directly into other domains' functions
within its own existing transaction — "only one responder ever handles
a request" holds regardless of how many domains that responder touches.
So the per-responder transaction boundary isn't going away, which means
truncate-between-tests isn't a placeholder — it's the answer, and this
section doesn't need revisiting when some other ticket lands.

## 6. Seeding

The existing seed mechanism (`Domain.Central.Responder.Api.Seed`) exists
to put required, valid reference data into the database on application
startup — `NodeStatus`/`NodeType` are lookup tables the app depends on to
function at all, and nothing in `migrations/` inserts rows (migrations
here are schema-only), so seeding is how those tables end up populated.
It is **not** demo or mock data, and doesn't create any `Project`/`Node`
rows at all. That's worth knowing before assuming it can just be reused
wholesale for tests: it's necessary but not sufficient for a test like
the `handlePostNode` pilot, which also needs a real `Project` and a root
`Node` to exist first — data this mechanism was never meant to provide.

**Recommendation:**
- Reuse `Seed.nodeStatuses`/`Seed.nodeTypes` directly (they're just plain
  data lists — trivially importable) for the lookup tables every test
  needs — this part genuinely is the same required reference data both
  the running app and a test need.
- Build minimal, test-specific fixtures (a `Project`, a root `Node`) with
  direct `insert` calls in each test's arrange step, rather than
  extending the seed mechanism to also cover this. Its job is
  "reference data the app needs to run," not "fixture data a test needs
  to assert on" — keep those two purposes separate rather than
  overloading one mechanism for both.

## 7. Where these tests live

A separate cabal `test-suite` component (e.g. `test-suite integration`),
distinct from the pure `spec` suite from #28. Keeps the fast, DB-free
unit suite fast and DB-free, and makes the (slower, Docker-dependent)
integration suite an explicit, separate target: `cabal test integration`
vs. `cabal test spec`.

## 8. CI implications — resolved in #72

#41 (unit tests in GitHub Actions) deliberately runs no database
service, because the unit suite doesn't need one. An integration suite
using `testcontainers` needs Docker available in the CI runner (GitHub
Actions' standard runners have it) but does **not** need a separately
configured Postgres *service container* the way a bare `docker run`
approach would — `testcontainers` manages its own container from inside
the test process. This is a distinct CI job/step from #41's, with its
own runtime cost, scoped as a follow-up to #41 rather than folded into
it.

**Can this only run when relevant files change?** Yes, but with a real
constraint learned the hard way while implementing #41: if this
integration-test check is ever made a **required** check for merging,
it must not be skipped via a top-level workflow `paths:` filter — a
required check that a path filter prevents from ever running stays
permanently "missing" rather than "passed," which blocks merging
entirely, with no admin bypass if `enforce_admins` is set (see
`docs/development/ci.md`'s "Why it always runs" section for the
incident this came from). The safe version of "only run when relevant"
is the pattern already adopted there: the job always runs, but a
`git diff`-based step decides whether to actually skip the expensive
steps via `if:`. If this check is never made required (e.g. kept
informational, or only run on-demand), a plain top-level `paths:` filter
is fine and simpler — the constraint only bites for a *required* check.

**Resolved (#72):** a separate workflow,
`.github/workflows/integration-test.yml`, runs `cabal test integration`
on every PR touching Haskell-relevant files, kept **informational, not
required** for now (so the required-check/`paths:`-filter trap above
doesn't apply — a plain top-level `paths:` filter is used, deliberately,
per the "not required" branch above). Promoting it to required is left
as a separate, later, deliberate branch-protection decision once the
suite has proven reliable. See `docs/development/ci.md` for the current
detail.

## 9. Cross-reference: #17's E2E spike

#17 will also need a seeded, disposable Postgres for its own tests (full
browser-driven flows need real backing data too). Whichever of #17 or
this spike's resulting implementation ticket lands first should build
the `testcontainers`-based test-database setup once; the other should
reuse it rather than standing up a second, differently-shaped answer to
the same problem. Given this doc's narrower pilot scope, the integration
suite is likely to land first — but that's not a hard requirement, just
the more probable order.

## 10. Open questions

- ~~Should the integration suite run on every PR once it exists, or only
  on-demand/nightly, given it's slower than the unit suite? Not decided
  here — a call for whoever implements #41's follow-up.~~ Resolved —
  every PR (touching relevant files), informational rather than
  required; see [§8](#8-ci-implications--resolved-in-72) and #72.
- If `testcontainers` setup proves to have too much friction (Docker-in-
  Docker issues in some CI environments, slow cold starts), revisit
  `ephemeral-pg` before assuming the whole approach needs to change.
- Once more than the pilot flow is covered, revisit whether per-test
  truncation still performs well, or whether a smarter reset strategy
  (e.g. one shared container per test-suite run, truncate only tables
  the just-finished test actually touched) is worth the added
  complexity.

## 11. Decision

Confirmed 2026-08-31. Every recommendation above is adopted as written,
with nothing changed on reconsideration:

- **Pilot target: `handlePostNode`** (§3) — the multi-table,
  foreign-key-driven write flow this doc argued for; the rest of the
  write/mutate handlers follow in their own tickets once this pilot
  proves out the approach.
- **Database: `testcontainers`** (§4) — over `ephemeral-pg` or reusing
  the dev Postgres container. Landed against the base `testcontainers`
  API directly rather than the `testcontainers-postgresql` wrapper
  originally tried in #65 — that wrapper didn't expose volume-mount
  support, which #65's own review turned out to need (see the next
  bullet).
- **Isolation: truncate the relevant tables between tests** (§5), not
  per-test transaction rollback — settled as the actual answer, not a
  placeholder, per the reasoning already recorded there once #50 was
  decided against. Re-migrate once per suite run, at container startup.
- **Seeding: reuse `Seed.nodeStatuses`/`Seed.nodeTypes` directly** for
  required lookup data; build minimal, test-specific fixtures (a
  `Project`, a root `Node`) by hand in each test's arrange step, rather
  than extending the seed mechanism to cover both purposes (§6).
- **Location: a separate `test-suite integration` cabal component**
  (§7), distinct from the pure `spec` suite, so the fast unit suite
  stays fast and DB-free.

**Left open, on purpose — not indecision:** §10's three open questions
were explicitly deferred to whoever implements this, per §8/§10's own
reasoning — nothing here was pre-decided in the absence of the
information (actual CI runtime, actual friction) those questions
depended on. The CI trigger cadence and required-vs-informational
question is now resolved (#72, see §8); falling back to `ephemeral-pg`
if `testcontainers` proves too much friction, and revisiting the
truncation strategy once more than the pilot flow is covered, remain
open.

**Implementation tracked in #65–#69, plus #72 for CI.** #65 (merged)
covered the infrastructure and the `handlePostNode` pilot; #66–#69
cover the remaining mutating responders (`Node.Description`,
`Node.Status`, `Node.Title`, `ProjectCreate.Submit`) as follow-ups now
that the pilot has proven out the approach; #72 wired the suite into CI
(§8). Now that #65 has landed and the suite actually exists, #53
(documenting this approach in `docs/development/`) is unblocked.
