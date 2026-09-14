# Unit Testing

A unit test suite exists, built with [Hspec](https://hspec.github.io/).
This doc covers how to run it and what it actually covers — for the
comparison of testing frameworks and the reasoning behind what's in and
out of scope, see
[`../solution-proposals/unit-testing.md`](../solution-proposals/unit-testing.md)
(§8 has the final decision this doc restates as current fact).

## Where tests live, and how to run them

Every spec file lives under `test/`, mirroring the module it covers —
e.g. `lib/src/Common/Validation.hs` is covered by
`test/Common/ValidationSpec.hs`. `Spec.hs` is a one-line
`hspec-discover` stub (`{-# OPTIONS_GHC -F -pgmF hspec-discover #-}`)
that auto-finds every `*Spec.hs` file under `test/` at build time —
adding a test module is just adding a file named `<Module>Spec.hs` in
the matching path; nothing else needs registering by hand.

One thing that **does** need registering by hand: `typeio.cabal`'s
`test-suite spec` stanza lists every spec module under `other-modules`.
A new spec file that isn't added there won't be picked up.

Run the suite locally:

```
cabal test
# or:
make test
```

Running this locally before pushing is optional — CI runs it on every
PR (see [`ci.md`](ci.md)) — but it's the fastest way to find a failure
without waiting on a CI run.

## What's actually covered

Not every module — tiered by how testable/valuable each layer is (full
rationale in the proposal's §4/§8):

- **`Common.Validation`** — the accumulating-validation combinators
  (`isThere`, `isNotEmpty`, `valRead`, `isBetween`, `runValidation`,
  `.$`) that every form/config validator in the app is built on,
  including the "logs an error but still passes the value through"
  behavior of `isNotEmpty`/`isBetween`/`isEq` — this is exactly the kind
  of non-obvious behavior a test suite exists to pin down (see the
  `Config.Db`/`Config.Web` specs for it in practice, and `CLAUDE.md`'s
  notes on the bugs this behavior has contributed to).
- **`Data.Either`**, **`Data.Text.Util`** — small pure helpers used
  throughout the app.
- **`App.Link`** — the URL builders. They are derived from the route
  type with `safeLink`, so the spec pins what the derivation actually
  emits: absolute paths, parameters in route-declaration order, an
  omitted optional one, and a percent-encoded free-text one (see
  [`backend/routing.md`](backend/routing.md#links-are-derived-not-written)).
- **`App.Params`** — the `FromHttpApiData` instances the routes parse
  with. What matters is not that a well-formed value parses but that a
  malformed one is refused, since that refusal is the route's 400.
- **`Config.App`/`Config.Db`/`Config.Web`** — the `validateConfig`
  functions specifically, since they're pure given a constructed lookup
  value (no real environment variables touched) and guard against a lot
  of silent startup failure (see
  [`backend/environment.md`](backend/environment.md)).

## What's deliberately out of scope

- **Pure helpers embedded inside handler modules** (`validate*`,
  `showNodeType`, `toGraph`, etc.) — small enough and close enough to the
  handler code that exercises them that testing them in isolation wasn't
  judged worth it.
- **Handlers themselves — no unit tests, on purpose.** A handler like
  `Node.Get.handler` runs its esqueleto query through `runDb` against a
  real `ConnectionPool`. Making that unit-testable would mean injecting a
  repository layer in front of the pool — and that option was **rejected
  outright, not deferred**. The cost is explicitly
  [Locality of Behavior](https://htmx.org/essays/locality-of-behaviour/):
  keeping what a handler does — including its actual query — visible in
  one place is valued over making that handler mockable in isolation.

  **Don't "fix" this by adding a repository layer** — it was a
  considered decision, not a gap. If query logic embedded in a handler
  grows complex enough that this tradeoff stops being worth it, that's a
  fresh discussion (open a new decision, don't just add mocking as a
  drive-by change).

  The answer for testing handlers is integration tests that drive the
  real application by URL against a real, ephemeral test database — see
  [`integration-testing.md`](integration-testing.md) for how to run them
  and what they cover, and
  [`../solution-proposals/integration-testing.md`](../solution-proposals/integration-testing.md)
  for the rationale behind each design choice. Out of scope for this
  doc either way — unit tests still don't cover handlers.

## Mocking (or: why there isn't a mocking library)

A handler's dependencies come from `Env`
([`backend/environment.md`](backend/environment.md)), which is a plain
record — so faking one means constructing an `Env` with a stub field,
not installing a framework. No mocking library is used or needed. See
the proposal's §5 for a worked example (faking `EntryLog` to assert on
what got logged without a real `fast-logger` backend).
