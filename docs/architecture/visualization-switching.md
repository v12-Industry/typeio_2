# Visualization Switching

> **Status: built.** A `visualizationMode` query parameter selects the
> drawing, and three visualizations exist: `Layered`, `Rootless` and
> `Orbital`. #213 wrote this design down before any of them, so the
> conventions were decided deliberately rather than set by whichever
> implementation landed first; #215 built the switch and the second
> visualization, #229–#241 the third.
>
> **The selection mechanism was replaced in #223, deliberately
> reversing what #213 decided.** This document used to say, flatly, that
> the choice happens "once, when the container is constructed — not per
> request, and not from a query parameter", and `GRAPH_VISUALIZATION`
> was that config value. It is gone. The reasoning that replaced it is
> in [Absent takes the default; wrong is an
> error](#absent-takes-the-default-wrong-is-an-error) and [The app has
> been here before](#the-app-has-been-here-before-and-it-is-not-the-same-mistake).
>
> Recorded plainly because `CLAUDE.md`'s #50 note warns that a
> documented decision is not proof of current behaviour — here the
> hazard is the opposite one: a decision that *was* built, and was then
> deliberately undone.
>
> **The isolation rule changed while it was being built, deliberately.**
> #213 said visualizations share *no* code and each owns a private copy
> of everything, including the layout engine. Building #215 priced that:
> it meant duplicating a ~1,500-line geometry engine so that one
> visualization could decline to draw one node, and every future fix to
> that geometry — #214's component packing was one, landed the same day —
> would have had to be applied twice. That was judged utopian and
> revised. The rule now draws the line at *policy* rather than at
> *directory*, and [The isolation rule](#3-the-isolation-rule) below is
> the current, normative version.
>
> **The seam moved again in #233, for the same reason the rule did:**
> the version written here could not express a visualization that is not
> layered, because `BuildGraph` returns a `ServerGraph` and a
> `ServerGraph` carries a `Diagram`. It is now `RenderGraph` — rows in,
> finished fragment out. That is a widening, not a reversal: what is
> shared, and the flag test, are unchanged.

The dependency graph may be the most important thing in this
application, and there is more than one good way to draw it. This
describes how the app holds several visualizations at once and picks
one.

## The shape of it in one paragraph

Every visualization is live in one process, and each **request** says
which drawing it wants: an optional `visualizationMode` query parameter,
falling back to a hardcoded default when absent. Each visualization owns
one function from a project's rows to the finished fragment. The
machinery for getting there — the layout engine, the queries, the SVG
vocabulary, the viewport frame — is shared infrastructure any
visualization may use, and two of the three use all of it, differing
only in which nodes and edges they hand it.

## 1. The request parameter

`visualizationMode`, camelCase like `projectId` and `nodeId`.

```haskell
-- Config.Visualization

data Visualization
  = Layered   -- root heads the drawing; containment edges derived
  | Rootless  -- the work only, nothing forced to converge (#215)
  | Orbital   -- radial, rootless, shared dependencies replicated (#229)
  deriving (Eq, Read, Show)

defaultVisualization :: Visualization
defaultVisualization = Orbital
```

Parsed with `valRead`, so the value is the constructor name, exactly how
`ENV` parses into `Config.App.EnvironmentName`. `Orbital` is the first
value here that selects a drawing built on something other than the
layered engine — see
[`orbital-dependency-weighted-graph.md`](orbital-dependency-weighted-graph.md).

### Absent takes the default; wrong is an error

The two cases are deliberately not the same:

| Request | Result |
|---|---|
| no `visualizationMode` | `defaultVisualization` |
| `visualizationMode=Orbital` | that drawing |
| `visualizationMode=Radial` | **403**, `Invalid visualizationMode value` |
| `visualizationMode=orbital` | **403** — `Read` is case-sensitive on constructor names |
| `visualizationMode=` (empty) | **403** — present and unparseable, not absent |

That last row is worth knowing because the friendlier reading is
tempting. `lookupVal` returns `Just ""` for an empty parameter, so it is
a value that does not parse rather than a missing one, and every other
optional query parameter in this app already behaves that way —
`?nodeId=` is rejected the same way by `ProjectManage.View`'s own
`valRead`. Special-casing this one field would make "empty" mean
something different depending on which parameter you left blank.

`GRAPH_VISUALIZATION` (#215–#223) had no fallback at all: a missing or
unparseable value failed at boot, on the reasoning that a server quietly
drawing the wrong graph does not announce itself — it surfaces much
later as "the graph looks wrong". **That reasoning survives for a value
somebody got wrong**, which is why an unrecognised mode is an error
rather than a fallback. It never applied to a value nobody supplied,
which is just an ordinary link.

This needs `valRead` *without* `isThere`, and deliberately not through
`runValidation`: that helper reads "no value and no errors" — exactly
what an absent optional field produces — as a failure, because it is
built for fields that must end up present. `validateVisualization`
spells the three cases out instead.

### The default is "whichever was added most recently"

Today `Orbital`. ⚠️ **Adding a visualization means changing that
binding**: it is the one part of this mechanism that does not update
itself, and nothing fails if it is forgotten — the app just keeps
serving the previous default. The convention exists so a new drawing is
seen rather than sitting behind a parameter nobody passes.

A spec or link that wants a *specific* drawing should name it rather
than rely on the default, precisely because the default moves.
`e2e/tests/graph.spec.ts` asks for `Layered` explicitly for that reason.

## 2. Where the switch happens

Two pieces. The table of what each visualization is, in
`Domain.Project.Responder.Ui.Container`:

```haskell
renderFor :: Visualization -> RenderGraph
renderFor Layered  = Layered.renderGraph
renderFor Rootless = Rootless.renderGraph
renderFor Orbital  = Orbital.renderGraph
```

and the endpoint that consumes it, in
`Domain.Project.Visualization.Common`:

```haskell
handleGraph :: (Visualization -> RenderGraph) -> ConnectionPool -> Application
```

`handleGraph` takes a **function**, not a `Visualization`: the shared
module never learns which drawings exist, it validates the parameter and
applies the table it was handed. The list of visualizations stays in one
place, and the shared request handling stays honest about being shared.

### The choice reaches the fragment, not just the page

Worth knowing, because it is the part that is easy to get wrong: the
browser navigates to `/ui/project/vw`, and the drawing arrives by a
*separate* htmx request to `/ui/project/graph`. So the project page
resolves `visualizationMode` and forwards it into that link
(`ProjectManage.Link.graphLink`). A parameter on the page URL alone
would do nothing at all.

It is forwarded as a rendered constructor name, never as text passed
through from the request, so nothing a caller sends can end up
concatenated into the link.

### The app has been here before, and it is not the same mistake

`?layout=server` was a request-time flag, removed in #181/#192. It is
worth saying why bringing one back is not a reversal of that decision:
`layout=server` selected between a server-rendered graph and a
client-rendered one *while both existed*, and it was removed because
nothing in the UI ever set it and the alternative it selected was gone.
It was a migration flag that outlived its migration.

`visualizationMode` selects between drawings that are all meant to
exist, all reachable, and all worth looking at. The cost that the
boot-time switch avoided — every drawing live in one process — is the
point rather than a side effect: it is what lets one link show a
colleague the orbital view of the same project without redeploying
anything.

## 3. The isolation rule

> A visualization decides **what the drawing is of**. Everything that
> turns that decision into a document is shared infrastructure.

Concretely, a visualization supplies one function:

```haskell
-- Domain.Project.Visualization.Common
type RenderGraph = Int64 -> [Entity M.Node] -> [Entity M.Dependency] -> Html ()
```

That is the whole per-visualization surface: rows in, finished fragment
out. Everything on either side of it — parsing the request, querying the
project, the error responses — is shared and identical whichever drawing
is selected.

**A layered visualization does not write one of these by hand.** It
composes the two shared pieces it already had:

```haskell
renderGraph pid ns ds = templateServerGraph (buildGraph pid ns ds)

type BuildGraph = Int64 -> [Entity M.Node] -> [Entity M.Dependency] -> ServerGraph
```

`Layered.buildGraph` keeps every node and derives the root's containment
edges; `Rootless.buildGraph` drops the root, derives nothing, and drops
any stored edge that referred to it. That one function is still the
whole of what those two differ by.

#### Why the seam is at *render*, not at *build* (#233)

`BuildGraph` was the seam until #233, and it could not stay there. A
`ServerGraph` carries a `Diagram`, and `serverGraph` produces one by
calling the layered layout engine:

```haskell
serverGraph pid lns les =
  ServerGraph { …, sgDiagram = layout defaultLayoutConfig lns les }
```

So every drawing expressible through `BuildGraph` is a layered one *by
construction* — `PlacedNode` has no angle, `PlacedEdge` is a polyline
with jump points, and `templateServerGraph` renders rects and orthogonal
paths. The escape hatch this document already promised below ("a
visualization that is not layered at all … brings its own geometry") was
not actually reachable through the seam as written.

Moving the seam out one step costs the layered visualizations one line
each and lets a radial or force-directed one import neither the engine
nor the template.

### What is shared

| Shared | Because |
|---|---|
| `Domain.Project.Graph.*` — the layered layout engine | Geometry, not policy. It takes nodes and edges and returns coordinates; it has no opinion about which nodes it was given. One copy means one place to fix a layout bug. |
| `Domain.Project.Model` and the esqueleto queries | The domain, not a drawing of it. Two visualizations asking the same question of the database is not coupling; duplicating the query would let them silently disagree about what "the project" is. |
| Request parsing, error responses (`handleGraphWith`) | Identical whichever drawing is selected. |
| `graphFrame` — the navigable shell (#242) | The viewport, not the drawing. Six load-bearing details (no `viewBox`, the base-size attributes, `#graph-zoom-layer`, the origin shift, the anchor conversion, and the script tag living *inside* the fragment) that every visualization needs identically and none of which are apparent from the markup. Hand-rolling it gets pan/zoom subtly wrong with nothing to catch it. |
| The SVG vocabulary — `edgeLine`, `nodeGroup`, `nodeLabel`, `arrowMarker`, `templateServerGraph` | Presentation primitives, the same tier as `Common.Web.Elements`. Available to any visualization; used in practice by the layered ones, since they are what draws rects and orthogonal paths. |
| `Data.*` / `Common.*` utilities | General-purpose library code. `wrapLabel` wraps text; it does not know what a graph is. |

### What is not shared

The `RenderGraph` itself: what the drawing is of, and what it looks
like. Between `Layered` and `Rootless` that difference is confined to
one `BuildGraph` — which nodes exist, which edges exist, and whether any
are derived — because they agree on everything downstream of it. A
visualization that agrees on less simply shares less.

### What a visualization must publish (#234)

The seam above says what a visualization *supplies*. This is the one
thing it *owes* the rest of the app:

> Every element a visualization draws for node `N` carries
> `data-node-id="N"`.

That is the whole obligation. The Project Manage UI's node hooks —
highlighting a node while its panel is open, flashing it after a title
edit — select on that attribute, so they work on any drawing without
knowing which one is on screen.

**Why an attribute and not the element id.** An id encodes an
assumption: exactly one element per node. That held while every
visualization drew a node once. The orbital visualization (#229) draws a
node once per dependent, and under an id-based selector every one of
these hooks silently degrades to "whichever element the browser matched
first" — the panel highlights one arbitrary copy, the edit flashes a
different one, and nothing errors.

Hyperscript applies `to <selector/>` to *every* match, so the same line
is correct for one element or five:

```
init add .node-highlight to <[data-node-id='42']/>
```

**The selectors stay inline, and that is deliberate.** There is no
shared `nodeSelector` helper, no client-side node registry, and no JS
module that knows how to find a node. Each behaviour is declared on the
element it governs, which is where this codebase keeps behaviour; three
sites constructing a similar selector is the cost of that and is not a
problem to solve. Moving it into a helper would buy nothing and put the
behaviour somewhere the reader of the markup cannot see it.

**`hx-target` is the exception, and it needs a different answer.** An
`hx-target` swaps one element however many match, so the per-node label
refresh cannot be fixed by changing its selector — see #244.

`#node-<id>` remains on the layered drawings alongside the attribute:
`graph-rendering.md` lists it as a contract and `graph.spec.ts` locates
nodes by it. This is additive.

### Where the seam moves if a visualization needs more

The shared pieces are shared because nothing yet needs them to differ,
not because they may never. A visualization that wants its own document
assembly — a frame drawn around the work instead of a root node, say —
writes its own `RenderGraph` and does not call `templateServerGraph`,
rather than bending the shared one with a flag. A visualization that is
not layered at all — a radial or force-directed one — simply does not
import `Domain.Project.Graph.*`; it brings its own geometry.

**Since #233 both of those are reachable rather than aspirational.**
Declining the engine and declining the template are now the same kind of
act: don't import it. Nothing has to be parameterised for a
visualization to opt out of either.

**The rule to hold is that a flag never crosses the seam.** If a shared
function grows a parameter whose only purpose is to say which
visualization is calling, that function has stopped being shared
infrastructure and should be moved into the visualizations that need it.
That is the failure mode the original no-shared-code rule was reaching
for, and it is worth keeping even though the blanket version was not.

## 4. Directory layout

```
lib/src/Domain/Project/
  Graph/                     -- shared: the layered layout engine
    Types.hs  Layer.hs  Order.hs  Coord.hs  Route.hs  Layout.hs
    Containment.hs           -- root-to-work derivation, used by Layered
  Visualization/
    Common.hs                -- shared: queries, request/response, SVG
    Layered/Responder.hs     -- buildGraph: root included
    Rootless/Responder.hs    -- buildGraph: root left out
```

`Domain.Project.Graph.*` did not move. It was already a pure,
dependency-free, visualization-agnostic tier — the neutral home the
revised rule calls for — so making it shared was a matter of saying so,
not of relocating it.

## 5. Testing

- **The shared engine stays in the unit tier.** It is pure and
  dependency-free (`docs/development/unit-testing.md`), and the hard
  rule in [`graph-rendering.md`](graph-rendering.md) — no `Database.*`,
  `persistent`, `Esqueleto`, `Lucid` or `Network.Wai` under
  `Domain.Project.Graph.*` — is what keeps it there.
- **Each visualization's conversion is integration-tested**, because it
  takes `Entity` values and renders markup. `Rootless.ResponderSpec`
  asserts what its conversion decides: no root drawn, no containment
  derived, root-referring edges dropped — plus the positive case, since
  every one of those would also pass on a visualization that drew
  nothing at all.
- **Every visualization is exercised**, not only the configured one.
  Both specs construct their handler directly rather than reading
  `GRAPH_VISUALIZATION`, so adding a visualization cannot quietly change
  what an existing test asserts.

## 6. How an issue says which visualization it is for

Labels, applied at issue-creation time. See
[`../development/labels.md`](../development/labels.md)'s `viz:*` section
— it is the normative reference, and this is a pointer to it.
