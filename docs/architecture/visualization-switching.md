# Visualization Switching

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
  | Rootless  -- the work only, nothing forced to converge
  | Orbital   -- radial, rootless, shared dependencies replicated
  deriving (Eq, Read, Show)

defaultVisualization :: Visualization
defaultVisualization = Orbital
```

Parsed with `valRead`, so the value is the constructor name, exactly how
`ENV` parses into `Config.App.EnvironmentName`. `Orbital` is the only
value that selects a drawing built on something other than the layered
engine — see
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

A value somebody got **wrong** fails loudly rather than falling back,
because a server quietly drawing the wrong graph does not announce
itself — it surfaces much later as "the graph looks wrong". A value
nobody supplied is not that; it is an ordinary link, and it takes the
default.

The empty case is worth knowing because the friendlier reading is
tempting. `lookupVal` returns `Just ""` for an empty parameter, so it is
a value that does not parse rather than a missing one, and every other
optional query parameter in this app behaves that way — `?nodeId=` is
rejected the same way by `ProjectManage.View`'s own `valRead`.
Special-casing this one field would make "empty" mean something
different depending on which parameter you left blank.

Expressed as one ordinary `runValidation` pipeline, like every other
validator in the app:

```haskell
lookupVal "visualizationMode" qt
  .$ unpack
  >>= valRead "Invalid visualizationMode value"
  >>= orDefault defaultVisualization
```

`orDefault` is what makes that possible. It is the counterpart to
`isThere` — that one says "absence is an error", this says "absence is
fine, use this instead". Crucially it **fills a missing value without
suppressing a bad one**: an error already recorded still fails the whole
validation, so an absent field takes the default while a
present-but-wrong one is still rejected. It has to come last in a chain,
for the reason its own docs give.

Without it, a pipeline ending in an absent optional field hands
`runValidation` a `(Nothing, [])` — no value and no errors — which it
reports as `"Unknown error in validation"`, because it is built for
fields that must end up present.

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
(`ProjectManage.Link.graphLink`). **A parameter on the page URL alone
would do nothing at all.**

It is forwarded as a rendered constructor name, never as text passed
through from the request, so nothing a caller sends can end up
concatenated into the link.

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
composes two shared pieces:

```haskell
renderGraph pid ns ds = templateServerGraph (buildGraph pid ns ds)

type BuildGraph = Int64 -> [Entity M.Node] -> [Entity M.Dependency] -> ServerGraph
```

`Layered.buildGraph` keeps every node and derives the root's containment
edges; `Rootless.buildGraph` drops the root, derives nothing, and drops
any stored edge that referred to it. That one function is the whole of
what those two differ by.

#### Why the seam is at *render*, not at *build*

`BuildGraph` cannot express a visualization that is not layered. A
`ServerGraph` carries a `Diagram`, and `serverGraph` produces one by
calling the layered layout engine:

```haskell
serverGraph pid lns les =
  ServerGraph { …, sgDiagram = layout defaultLayoutConfig lns les }
```

So every drawing expressible through `BuildGraph` is a layered one *by
construction* — `PlacedNode` has no angle, `PlacedEdge` is a polyline
with jump points, and `templateServerGraph` renders rects and orthogonal
paths. Putting the seam one step further out costs the layered
visualizations one line each and lets a radial or force-directed one
import neither the engine nor the template.

### What is shared

| Shared | Because |
|---|---|
| `Domain.Project.Graph.*` — the layered layout engine | Geometry, not policy. It takes nodes and edges and returns coordinates; it has no opinion about which nodes it was given. One copy means one place to fix a layout bug. |
| `Domain.Project.Model` and the esqueleto queries | The domain, not a drawing of it. Two visualizations asking the same question of the database is not coupling; duplicating the query would let them silently disagree about what "the project" is. |
| Request parsing, error responses (`handleGraphWith`) | Identical whichever drawing is selected. |
| `graphFrame` — the navigable shell | The viewport, not the drawing. Six load-bearing details (no `viewBox`, the base-size attributes, `#graph-zoom-layer`, the origin shift, the anchor conversion, and the script tag living *inside* the fragment) that every visualization needs identically and none of which are apparent from the markup. Hand-rolling it gets pan/zoom subtly wrong with nothing to catch it. |
| The SVG vocabulary — `edgeLine`, `nodeGroup`, `nodeLabel`, `arrowMarker`, `templateServerGraph` | Presentation primitives, the same tier as `Common.Web.Elements`. Available to any visualization; used in practice by the layered ones, since they are what draws rects and orthogonal paths. |
| `Data.*` / `Common.*` utilities | General-purpose library code. `wrapLabel` wraps text; it does not know what a graph is. |

### What is not shared

The `RenderGraph` itself: what the drawing is of, and what it looks
like. Between `Layered` and `Rootless` that difference is confined to
one `BuildGraph` — which nodes exist, which edges exist, and whether any
are derived — because they agree on everything downstream of it. A
visualization that agrees on less simply shares less.

### What a visualization must publish

The seam above says what a visualization *supplies*. This is the one
thing it *owes* the rest of the app:

> Every element a visualization draws for node `N` carries
> `data-node-id="N"`.

That is the whole obligation. The Project Manage UI's node hooks —
highlighting a node while its panel is open, flashing it after a title
edit — select on that attribute, so they work on any drawing without
knowing which one is on screen.

**Why an attribute and not the element id.** An id encodes an
assumption: exactly one element per node. The orbital visualization
draws a node once per dependent, and under an id-based selector every
one of these hooks degrades to "whichever element the browser matched
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
refresh cannot be fixed by changing its selector: each drawn element
carries its own hook aimed at its own label.

`#node-<id>` remains on the layered drawings alongside the attribute:
`graph-rendering.md` lists it as a contract and `graph.spec.ts` locates
nodes by it. The attribute is additive.

### Where the seam moves if a visualization needs more

The shared pieces are shared because nothing needs them to differ, not
because they may never. A visualization that wants its own document
assembly — a frame drawn around the work instead of a root node, say —
writes its own `RenderGraph` and does not call `templateServerGraph`,
rather than bending the shared one with a flag. A visualization that is
not layered at all — a radial or force-directed one — simply does not
import `Domain.Project.Graph.*`; it brings its own geometry.

Both are ordinary acts rather than special cases: declining the engine
and declining the template are the same thing, which is not importing
it. Nothing has to be parameterised for a visualization to opt out of
either.

**The rule to hold is that a flag never crosses the seam.** If a shared
function grows a parameter whose only purpose is to say which
visualization is calling, that function has stopped being shared
infrastructure and should be moved into the visualizations that need it.

## 4. Directory layout

```
lib/src/Domain/Project/
  Graph/                     -- shared: the layered layout engine
    Types.hs  Layer.hs  Order.hs  Coord.hs  Route.hs  Layout.hs
    Containment.hs           -- root-to-work derivation, used by Layered
  Orbit/                     -- the orbital visualization's own geometry
    Types.hs  Unfold.hs  Layout.hs
  Visualization/
    Common.hs                -- shared: queries, request/response, SVG
    Layered/Responder.hs     -- buildGraph: root included
    Rootless/Responder.hs    -- buildGraph: root left out
    Orbital/                 -- radial; imports no Graph.* at all
      Responder.hs  View.hs
```

`Domain.Project.Graph.*` and `Domain.Project.Orbit.*` are siblings, not
a hierarchy: both are pure, dependency-free geometry tiers, and neither
imports the other. A visualization uses whichever suits the drawing it
makes, or brings a third.

## 5. Testing

- **Both geometry tiers stay in the unit tier.** They are pure and
  dependency-free (`docs/development/unit-testing.md`), and the hard
  rule in [`graph-rendering.md`](graph-rendering.md) — no `Database.*`,
  `persistent`, `Esqueleto`, `Lucid` or `Network.Wai` under
  `Domain.Project.Graph.*`, and the same under `Domain.Project.Orbit.*`
  — is what keeps them there.
- **Each visualization's conversion is integration-tested**, because it
  takes `Entity` values and renders markup. `Rootless.ResponderSpec`
  asserts what its conversion decides: no root drawn, no containment
  derived, root-referring edges dropped — plus the positive case, since
  every one of those would also pass on a visualization that drew
  nothing at all.
- **Every visualization is exercised**, not only the default one. Each
  spec constructs its handler directly, so adding a visualization cannot
  quietly change what an existing test asserts. The switch itself is
  covered separately, driving `handleGraph` with the real `renderFor`
  table so a spec cannot pass against a table that has lost an entry.

## 6. How an issue says which visualization it is for

Labels, applied at issue-creation time. See
[`../development/labels.md`](../development/labels.md)'s `viz:*` section
— it is the normative reference, and this is a pointer to it.
