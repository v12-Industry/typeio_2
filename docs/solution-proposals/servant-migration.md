# Solution Proposal: Replacing the Bespoke Web Layer with Servant

- **Status:** Decided — see §8. Implementation tracked in
  #328–#341 under `epic:migrate-servant`.
- **Date:** 2026-09-12
- **Related:** #313 (stale docs pointing at a module the layered removal
  deleted), the audit findings this proposal opens with, and
  `docs/solution-proposals/haskell-graph-rendering.md` (which established
  the server-side rendering approach this migration must preserve)

## 1. Problem statement

The web layer is hand-rolled on WAI/Warp: a tree router built from
`Data.HashTree` combinators, a `Container` record per domain for
dependency wiring, request parsing via `Common.Validation`, and URLs
built by string concatenation in `ProjectManage.Link`.

It works, and it is small — roughly 320 lines across `Platform.Web.*`
and `Container.*`. But an audit of the codebase found five live defects,
and four of them are properties of that hand-rolled layer rather than
mistakes within it:

- **`findPath` matches path prefixes.** It returns at the first `Node`
  and discards the rest of the path, so `/api/project/nodes/anything`
  serves the node list. Every endpoint has an infinite family of
  aliases.
- **`addT` silently discards a route** registered under an existing
  leaf: `addT (Node x) _ _ = Node x`. A duplicate registration vanishes
  with no warning.
- **`Common.Validation.valRead` parses untrusted input with
  `readMaybe`,** which implements Haskell literal syntax. Verified
  against this project's GHC: `readMaybe "0x1F" :: Maybe Int` is
  `Just 31`, so `?projectId=0x1F` resolves to project 31. Leading and
  trailing whitespace are accepted too.
- **URLs are concatenated by hand.** This has already produced a
  shipped bug: `queryTextToText` folded its accumulator on the wrong
  side, so every rebuilt query string came back reversed with a
  trailing `&`. Two parameters hid it; five did not.

A fifth property is structural rather than a defect: `rootTree` takes
the `Request` and returns the route tree, so the entire routing
structure — six `HashMap`s and every handler closure — is rebuilt on
every request. The cause is that `Container` mixes fields of type
`Application` with fields of type `Application` already applied to a
request.

These are all fixable in place. The question this proposal answers is
whether fixing them by hand is the right use of the effort, given that
a framework whose central idea is exactly this problem already exists.

## 2. The circumstances that make now the moment

Two facts change the economics, and both are temporary.

**Nothing is deployed and no database is provisioned.** There is no data
to migrate, no cutover window, no rollback plan, no dual-write period
and no users to keep online. The cost of this decision is code and
learning time, and nothing else. That is not a normal position to be in
and it will not last.

**The test suites are framework-independent.** `test-integration/`
(1,801 lines) drives handlers through `Network.Wai.Test` — that is,
against a WAI `Application`. Servant, Yesod and Scotty all *produce* a
WAI `Application`, so that suite keeps working across the migration. The
Playwright suite (903 lines) drives a browser and never knew what was
underneath. Combined with the unit suite over the pure layer, that is a
regression harness that survives the change, which is the single
biggest de-risking factor available here.

## 3. What a framework would actually replace

"Rewrite the web layer" sounds larger than it is. Measured against the
current tree:

| Layer | Lines | Fate |
|---|---|---|
| `Domain.Project.Graph.*`, `Domain.Project.Orbit.*` | 1,214 | untouched — pure, no WAI, no DB, no Lucid |
| `Domain.Project.Responder.*` | 2,331 | Lucid views survive; the outer plumbing of each handler changes |
| `Domain.Project.Visualization.*` | 769 | rendering survives; the responder seam changes |
| `Config.*`, `Environment.*`, `Logging.*` | 593 | untouched |
| `Platform.Web.*` | 288 | replaced |
| `Container.*` | 33 | replaced |

So the genuinely replaced surface is about **320 lines**, plus the outer
ten-to-twenty lines of each of 32 responder modules — the part that
parses a query string, picks a status code and calls `responseLBS`.

## 4. Options considered

### 4.1 Servant

Describes the API as a type and checks handlers against it.

- The prefix-matching bug is **unexpressible**: a route either consumes
  the whole path or does not match.
- Query and path parameters parse through `FromHttpApiData`, which is
  decimal-correct — the `0x1F` case becomes a 400.
- `safeLink` derives URLs from the route type, so a route change breaks
  every caller at compile time.
- The server is a value built once; there is no per-request tree.
- Lucid views carry over unchanged via `servant-lucid`, which supplies
  the `HTML` content type and a `MimeRender` instance for `Html ()`.

Cost: the type errors when an API type and a handler disagree are long
and structural, and there is a learning curve in front of them. The
ecosystem's marquee extras — `servant-client`, `servant-openapi3` — are
API-shaped and mostly unused by an HTML application, though
`servant-client` may earn its place in the integration suite.

One genuine ergonomic wart for an HTML app: redirects are thrown as
errors (`throwError err302 { errHeaders = … }`). A redirect is not an
error, and this application redirects in at least one place today (the
`visualizationMode` fallback).

### 4.2 Yesod

Type-safe routes via Template Haskell, and `persistent` is already a
Yesod-family library, so half the stack is in use here already. It
solves the same routing and URL problems, and adds sessions, CSRF,
authentication and forms.

Rejected because its value is concentrated in features this application
either does not have or does not need centrally. The decisive factor was
auth: the one thing Yesod offers that Servant does not is
`isAuthorized`, a single choke point consulted for every route before
any handler runs. **Decentralized auth management is acceptable for this
application**, which removes that advantage.

Adopting it would also mean abandoning Lucid for Hamlet to get the
benefits worth having — and `docs/development/ui/` records that "there
are no template files" as a deliberate stance. Yesod's widget system,
which aggregates JS and CSS into a page's `<head>`, is also of little
use to an htmx application that returns fragments with no `<head>` at
all.

### 4.3 Scotty

A thin Sinatra-style layer over WAI. Migration would be close to
mechanical and could be done in two or three days.

Rejected because the current codebase *is already a Scotty-shaped
framework* — a route table built from combinators, handlers stored in
records, middleware composed over WAI, parameters pulled from a query
string by hand. Moving would delete `HashTree` and its two bugs, which
is worth something, and then stop. Routes stay untyped strings, so the
URL-construction problem is untouched, and `Parsable` for `Int` is
`Read`-based, so the hex-literal finding survives.

### 4.4 IHP — considered and set aside

The most productive Haskell web framework to start a greenfield project
in, with generators, a live-reloading dev server and built-in auth. Set
aside because adopting it means switching ORM (its own query DSL rather
than persistent/esqueleto), view layer (HSX rather than Lucid), schema
workflow (its schema file rather than `migrations/` and the `migrate`
CLI) and build toolchain (Nix) simultaneously. The pure layout engines
would survive; almost nothing else would. That is a new application that
reuses this one's algorithms, not a framework migration.

## 5. Why Servant fits this application in particular

Beyond the defect-by-defect match, two properties matter here.

**Content-type polymorphism is in the core, not bolted on.** `Get` takes
a type-level list of content types — `Get '[JSON] User` — and `JSON` is
one instance of `Accept`/`MimeRender` among others. `servant-lucid` is a
roughly twenty-line package. Servant is an HTTP interface description
library that is best known for JSON, not a JSON framework.

**htmx's protocol is headers, and Servant types headers.** `HX-Request`,
`HX-Push-Url` and friends can appear in the API type in both
directions:

```haskell
type NodePanel =
  "ui" :> "project" :> "node" :> "panel"
    :> Header "HX-Request" Text
    :> QueryParam' '[Required, Strict] "nodeId" NodeId
    :> Get '[HTML] (Headers '[Header "HX-Push-Url" Text] (Html ()))
```

The `#container`-versus-`#view` distinction is currently an implicit
convention spread across `hx-target` attributes and the index-render
middleware. It can become a stated part of the interface.

## 6. Migration shape

Stand up alongside, copy across, delete the old one:

1. A second library and executable in the same package, built by the
   same `cabal build all`, so both applications exist simultaneously
   and can run on different ports.
2. Move the framework-independent modules — the pure layout engines, the
   model, config, environment, logging, the Lucid helpers.
3. Port endpoints **by domain rather than by layer**, keeping all three
   suites green throughout: infrastructure and middleware first, then
   the JSON API, then each UI surface.
4. Replace the hand-built URL builders with `safeLink` once every route
   exists.
5. Realign the integration suite, verify the E2E suite.
6. Delete the bespoke application, its dependencies and its
   documentation.

There is never a big-bang switch, and at every step the previous
application is still there and still working.

## 7. What is explicitly deferred

**All schema changes.** The `persistent` model, the SQL in
`migrations/` and the seeded reference data stay exactly as they are for
the whole of this epic. The audit identified several worthwhile schema
changes — `String` columns that should be `Text`, a closed status
vocabulary modelled as an open `String` with an `IsString` instance, an
unenforced soft-delete column, and a `project_root` node type whose
graph-side machinery is already unreachable — and mixing those into a
framework migration would make both harder to review and harder to
revert.

That work is worth doing, and it is cheapest while no database is
provisioned. It gets its own epic.

Also deferred, though smaller: collapsing the three near-identical node
field-update responders, and splitting the 504-line
`Visualization.Common`. Both are tempting to do while porting; both are
easier to review as their own change.

## 8. Decision

**Adopt Servant.** Stand it up alongside the existing application,
port by domain, and remove the bespoke stack once all three test suites
pass against the new one. No schema changes as part of this work.

The deciding factors, in order:

1. Four of the five audit defects stop being possible rather than being
   fixed — and the fifth, the per-request route tree, goes with the
   `Container` records.
2. Every asset worth keeping survives: Lucid, persistent/esqueleto, the
   WAI middleware stack, and all three test suites.
3. Decentralized auth management is acceptable, which removes Yesod's
   one distinguishing advantage and leaves it a larger framework for
   features this application does not need.
4. Nothing is deployed, so the cost is time and the risk is close to
   zero. That will not be true for much longer.
