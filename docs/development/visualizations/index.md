# Visualizations

The project dependency graph can be drawn more than one way. This directory
documents each drawing the app actually serves — what it draws and where
its code lives. For *how the app holds several visualizations and picks
one* (the switching mechanism, the shared queries, the isolation rule
between visualizations), see
[`../../architecture/visualization-switching.md`](../../architecture/visualization-switching.md) —
that document is the normative reference for the mechanism; this directory
is the per-visualization reference for what each one actually draws.

- [**Layered**](layered.md) — the project root heads the drawing, with
  its edges to the work derived (`viz:layered`).
- [**Rootless**](rootless.md) — the work only, with the project root left
  out entirely (`viz:rootless`).
- [**Orbital**](orbital.md) — radial rather than layered, with a shared
  dependency replicated into every work stream that waits on it
  (`viz:orbital`). The default.

The first two share one layout engine and SVG vocabulary — see
[`../../architecture/graph-rendering.md`](../../architecture/graph-rendering.md)
for that pipeline, which neither of those two docs repeats. Orbital
brings its own geometry and shares none of it; its design is in
[`../../architecture/orbital-dependency-weighted-graph.md`](../../architecture/orbital-dependency-weighted-graph.md).
