# The Orbital Visualization

`viz:orbital`: the work drawn as rings around an empty centre, one
radial tree per **head** — a node nothing is waiting on. A head sits
innermost, its dependencies on the next ring out, theirs beyond that.
Ring index is dependency depth.

The one thing to know before reading anything else: **a node is drawn
once per dependent it has.** A dependency shared by three work streams
is three circles, not one circle with three lines leaving it. That is
what "dependency-weighted" means, and everything else follows from it —
the absence of crossings, the role of colour, the DOM ids.

For the design and its contracts in depth, see
[`../../architecture/orbital-dependency-weighted-graph.md`](../../architecture/orbital-dependency-weighted-graph.md).
For the mechanism that selects this visualization, see
[`../../architecture/visualization-switching.md`](../../architecture/visualization-switching.md).
Neither is repeated here.

## What it draws

- **The work only.** The project root is filtered out before layout,
  the same as *Rootless*. The centre of the orbit is empty.
- **Every dependency between two drawn nodes**, as a straight segment
  trimmed to the two rims, arrowhead on the **inner** end — the
  dependent, the one waiting. Reading outward from a head tells you
  everything that deliverable is waiting on, in order.
- **A node once per work stream that reaches it.** Replicating a node
  replicates its whole subtree along with it: if `E` is drawn twice,
  everything `E` depends on is drawn twice too.

The consequence worth stating plainly: **there are no crossing edges at
all.** Not minimised — structurally absent, because every drawn node has
exactly one dependent and every tree owns a disjoint wedge of the
circle. That is the trade this drawing makes, and the price is that one
circle no longer means one node.

## Reading the drawing

Three things a reader has to know, and all three are in the markup:

1. **A circle is a *drawing* of a node, not the node.** The same node
   can appear several times.
2. **Colour ties replicas together.** Every replica of a node has the
   same hue; different nodes get hues spread around the wheel by a
   golden-angle rotation over the node's id. The hue is emitted per
   circle as a `--node-hue` custom property and the stylesheet computes
   the fill from it — what the server sends is *which node this is*, not
   an appearance decision.
3. **Hovering one replica highlights all of them.** Colour alone stops
   scaling after a few dozen nodes, so hovering any circle adds
   `.replica-hover` to every element sharing its `data-node-id`. CSS
   cannot express this on its own — there is no selector for "every
   element sharing an attribute value with the hovered one" — which is
   why it is a hyperscript behaviour on the circle rather than a
   stylesheet rule.

Clicking any replica opens the same node's detail panel, and editing the
title refreshes every replica's label.

## Selecting it

`?visualizationMode=Orbital` on the request — either on the graph
fragment directly, or on the project page, which forwards it:

```
/ui/project/vw?projectId=1&visualizationMode=Orbital
```

**This is the default**: a request naming no visualization gets it. An
unrecognised value is a validation error rather than a silent fallback.
See
[`../../architecture/visualization-switching.md`](../../architecture/visualization-switching.md).

## Where the code lives

Two trees, and the split between them is the point:

- `Domain.Project.Orbit.*` — the pure geometry, a sibling of
  `Domain.Project.Graph.*` rather than a part of it.
  - `Orbit.Types` — `OrbitNode`, `OrbitEdge`, the unfolded `OrbitTree`,
    the placed `Disc` and `Link`, `OrbitDiagram`, and `OrbitConfig` with
    its `defaultOrbitConfig`.
  - `Orbit.Unfold` — `heads`, and `unfold`, which turns the dependency
    DAG into the forest of in-trees and numbers each node's replicas.
  - `Orbit.Layout` — `orbit`, the entry point: allocate angles by leaf
    count, derive each ring's radius from what actually has to fit on
    it, place the discs and trim the links.
- `Domain.Project.Visualization.Orbital.*` — the web-facing half.
  - `Orbital.Responder` — drops the project root, keeps the dependency
    edges whose both ends survive, and calls `orbit`.
  - `Orbital.View` — the SVG: `<circle>` per disc, `--node-hue`, the
    replica-hover behaviour, and the per-replica ids and refresh hooks.

**It imports none of `Domain.Project.Graph.*`.** No layer assignment, no
ordering, no orthogonal routing, no `Diagram`. That is the clearest
single illustration of visualization-switching.md's isolation rule in
the codebase — the rule exists for exactly this case, and this is the
case.

What it does share is the part that was never about geometry, all in
`Domain.Project.Visualization.Common`: `validateProjectId`, the node and
dependency queries, the error responses, `graphFrame`, and the
node-detail links. `graphFrame` takes a neutral `FrameBox`, so
describing a rectangle does not require importing the layered engine.

## The DOM contract

The layered drawings use `#node-<id>` and `#node-text-<id>`. Replicas
break both — several elements would carry the same id — so this
visualization uses its own prefix:

| Selector | |
|---|---|
| `#tree-container`, `#tree-view`, `#graph-zoom-layer` | Unchanged, which is what lets `graph-viewport.js` work here with no modification |
| `#graph-nodes`, `#graph-links` | Unchanged |
| `#disc-<id>-<replica>` | One drawn circle. Replaces `#node-<id>` |
| `#disc-text-<id>-<replica>` | Its label. Replaces `#node-text-<id>` |
| `data-node-id="<id>"` | The identity handle — shared by every replica, and what the hover behaviour selects on |
| `.disc` | The group. Replaces `.node` |

A different prefix rather than a longer `#node-` id is deliberate:
anything still querying `#node-<id>` should find *nothing* in an orbital
drawing rather than silently match one arbitrary replica.

`.node` becoming `.disc` means the orbital rules in
`static/styles/views/manage-project.css` are its own rather than
inherited — the two drawings size and colour their shapes differently,
so sharing a class would make every layered tweak a change here too.

## Things that surprise people

- **A project with no dependency rows draws one ring and no arrows.**
  Every node is its own head, so every node is its own single-disc
  stream. That is the algorithm working correctly on the data it has.
  No UI flow creates a dependency — the only writer of
  `project.dependency` is the seed endpoint — so `make seed-db` is what
  gives you something to look at.
- **Rings are not evenly spaced.** Each ring's radius is derived from
  the angular crowding on that particular ring, which keeps the centre
  small on shallow projects instead of sizing everything for the worst
  ring.
- **Adding one dependency can redraw the whole picture.** The drawing is
  deterministic for a given input, but a new edge can re-partition the
  streams. This is a known cost of unfolding, not a defect.
- **`cfgMinRingGap` is clearance between rims, not centre-to-centre.**
  Read the other way, radially adjacent discs come out exactly tangent
  and their links are trimmed to zero length — a drawing with no visible
  arrows that no overlap assertion catches, because tangency is not
  overlap.

## Testing

Unit, on the pure geometry:

- `test/Domain/Project/Orbit/UnfoldSpec.hs` — heads, replication (once
  per dependent, whole subtree with it, replicas numbered across the
  forest), determinism and row-order independence, and the inputs that
  should not exist: cycles, self-dependencies, duplicate edges, empty
  graphs.
- `test/Domain/Project/Orbit/LayoutSpec.hs` — the invariants, asserted
  on every fixture: no two discs overlap, no two links cross, no link
  passes through a disc, every link has a visible length, radius
  increases with ring, and a disc stays inside its own subtree's angular
  span. The no-crossings claim is this visualization's whole premise, so
  it is tested rather than argued from the construction.

Integration, on rendered markup:
`test-integration/Domain/Project/Visualization/Orbital/ResponderSpec.hs`
— circles and no project root, replicas with distinct ids and a shared
`data-node-id`, same hue across replicas and different hues across
nodes, the hover behaviour, the per-replica refresh hooks, the id prefix
not being the layered one, and no root anchor emitted.

E2E: `e2e/tests/orbital.spec.ts` drives the browser — a node with
several dependents is drawn once per dependent, hovering one replica
highlights them all, clicking any replica opens the node panel, editing
a title updates the label on every replica, the discs are visibly clear
of each other, and the viewport pans without reloading.

Note that `typeio.cabal`'s `test-suite spec` stanza lists every spec
module under `other-modules` by hand. A new spec file that isn't added
there is silently never run.
