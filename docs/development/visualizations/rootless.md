# The Rootless Visualization

`viz:rootless`: the work, without the project node. The
root is left out of the drawing entirely, and nothing forces the work to
converge on a single box.

For the mechanism that selects this visualization, see
[`../../architecture/visualization-switching.md`](../../architecture/visualization-switching.md).
For the layout pipeline it draws with (layer assignment, ordering,
coordinates, edge routing), see
[`../../architecture/graph-rendering.md`](../../architecture/graph-rendering.md) —
that pipeline is the shared layered layout engine and isn't repeated
here.

## What it draws

- **The work nodes only.** The project root (`RootNode`) is filtered out
  before layout ever sees it.
- **Only the dependencies between work nodes that remain.** Any stored
  `project.dependency` edge with either end pointing at the root is
  dropped along with the root — kept only when *both* ends are still in
  the drawing. `layout` is total and would otherwise place the missing
  end at the origin and draw a stray arrow into empty space (see
  `Domain.Project.Visualization.Rootless.Responder.buildGraph`).
- **No containment edges.** A containment edge is how a drawing depicts
  a project's membership of its work; not depicting membership at all is
  this visualization's entire premise, so nothing is derived here.
- **Each node coloured by its status.** The shape carries
  `status-<id>` beside its `.work` class — `class="work status-active"`
  — and `manage-project.css` turns that into a fill from the
  `--status-hue-*` tokens in `global.css`. The point is that the state
  of the work is readable off the drawing without opening a node.

  Saturation and lightness are shared by all four statuses so the set
  reads as one palette, and the lightness is held down because a node's
  label sits directly on the fill. A status with no rule in the
  stylesheet keeps the plain `.work` fill rather than vanishing.

The project's own row is untouched in the database and still names the
project elsewhere in the UI (e.g. the project index) — it just isn't a
node in this particular drawing.

## Why this exists

The root is free to draw on a project that is one single chain, but it's
the dominant source of visual mess on a project with several parallel
workstreams — every workstream's head has to attach to it, and that
fan-out is what produces most of the bends and edge crossings. Measured
with the same layout engine on synthetic fixtures: four independent
workstreams went from 8 bends and 2 crossings with the root drawn to
zero of each with it left out; six parallel chains went from 6 crossings
to 0.

## Selecting it

`?visualizationMode=Rootless` on the request — either on the graph
fragment directly, or on the project page, which forwards it:

```
/ui/project/vw?projectId=1&visualizationMode=Rootless
```

A request naming no visualization gets the hardcoded default, which is
whichever was added most recently — today `Orbital`, not this one. An
unrecognised value redirects to the default rather than failing.
See
[`../../architecture/visualization-switching.md`](../../architecture/visualization-switching.md).

## Where the code lives

- `Domain.Project.Visualization.Rootless.Responder` — this visualization's
  entire distinguishing logic: `buildGraph` filters out the root, then
  keeps only the dependency edges whose both ends survived that filter.
- Everything else is shared infrastructure it uses rather than owns:
  `Domain.Project.Graph.*` (the layout engine), and
  `Domain.Project.Visualization.Common` (request parsing, the queries,
  error responses, and the SVG vocabulary). See
  visualization-switching.md's isolation rule for what "shared" means
  here and where the line sits if this visualization ever needs its own
  document assembly.

## Testing

`test-integration/Domain/Project/Visualization/Rootless/ResponderSpec.hs`
asserts, against rendered markup, the three ways this conversion could
quietly grow a root it is not supposed to have:

1. No project root is drawn.
2. No containment edge is derived.
3. A stored dependency that referred to the root is dropped, rather than
   surviving into layout pointing at a node that's no longer there.

It also covers the positive case — the work itself still renders — since
every one of the three assertions above would also pass on a
visualization that drew nothing at all.
