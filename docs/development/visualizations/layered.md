# The Layered Visualization

`viz:layered`: the whole project in rows by dependency depth, headed by
the project node. Work sits below the thing waiting on it, and every
node hangs off the root somewhere, so the drawing is one connected
shape.

For the mechanism that selects this visualization, see
[`../../architecture/visualization-switching.md`](../../architecture/visualization-switching.md).
For the layout pipeline it draws with (cycle breaking, layer assignment,
dummy insertion, ordering, coordinates, edge routing) and the SVG it
produces, see
[`../../architecture/graph-rendering.md`](../../architecture/graph-rendering.md) —
that document is the deep reference for the engine, it is shared with
the rootless visualization, and none of it is repeated here.

## What it draws

- **Every node in the project, including the project root.** Nothing is
  filtered out before layout.
- **Every stored dependency**, drawn as an arrow from the dependency up
  into the node waiting on it.
- **Containment edges from the root, derived rather than stored.**
  Membership lives in `node.project_id`; `Graph.Containment` turns it
  into edges at draw time, attaching the root to the *heads* of the work
  — the nodes nothing else is waiting on — and to nothing else. A node
  deeper in a chain already reaches the root through its own dependent.
  The two kinds are distinguishable in the markup: a derived edge is
  classed `link link-contains`, a stored one just `link`.

The root heading the drawing is the whole difference from *Rootless*,
which leaves it out and derives nothing. It is also the reason this
drawing always has a single top: `graphFrame` is handed the root's
placed position as the viewport anchor, so the browser opens the graph
centred on the project rather than on an arbitrary corner.

## Why this exists

It is the drawing that answers "what is this project, and what is
blocking what" in one view. Depth on the page *is* dependency depth, so
a chain reads top to bottom, and parallel work reads side by side. The
cost is the root's fan-out — on a project with several independent
workstreams every head attaches to the root, and that fan-out is the
dominant source of bends and crossings. That cost is exactly what the
other two visualizations trade away.

## Selecting it

`?visualizationMode=Layered` on the request — either on the graph
fragment directly, or on the project page, which forwards it:

```
/ui/project/vw?projectId=1&visualizationMode=Layered
```

A request naming no visualization gets the hardcoded default, which is
`Orbital`, not this one. An unrecognised value is a validation error
rather than a silent fallback. See
[`../../architecture/visualization-switching.md`](../../architecture/visualization-switching.md).

## Where the code lives

- `Domain.Project.Visualization.Layered.Responder` — small, because this
  visualization is the one the shared machinery was written around.
  `buildGraph` converts the entities to layout nodes and edges, appends
  the derived containment edges, and hands the lot to `serverGraph`;
  `renderGraph` templates the resulting diagram.
- `Domain.Project.Graph.Containment` — `containmentEdges`, the one piece
  of drawing logic that belongs to this visualization alone. *Rootless*
  does not call it and *Orbital* has no notion of it.
- `Domain.Project.Graph.*` otherwise — the layout engine, shared with
  *Rootless*.
- `Domain.Project.Visualization.Common` — request parsing, the node and
  dependency queries, error responses, the SVG frame, and
  `templateServerGraph`, which turns a laid-out `Diagram` into the
  markup. Shared.

That leaves this visualization owning roughly a dozen lines of its own.
See visualization-switching.md's isolation rule for what "shared" means
here and where the line sits if it ever needs its own document assembly.

## Testing

`test-integration/Domain/Project/Responder/Ui/ProjectManage/GraphSpec.hs`
covers this visualization against rendered markup: node shapes and their
kind classes, the node-identity contract (`data-node-id` and
`#node-<id>`), the label refresh hook, the viewport's emitted size and
root anchor, and containment — that the root is drawn above its work,
that the edge is derived rather than read from a dependency row, that it
carries an arrowhead like any other, and that it reaches a chain through
its head only.

`test/Domain/Project/Graph/LayerSpec.hs` covers the layout engine's
phases as pure functions, independently of any visualization.

`e2e/tests/graph.spec.ts` drives the drawing in a browser — clicking a
node opens its panel, and because the server places nodes
deterministically that click is a real one, which doubles as a check
that nodes land somewhere visible.
