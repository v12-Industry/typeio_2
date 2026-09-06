# Architecture

How parts of this system are **designed**: module structure, the
contracts between components, the invariants they guarantee, and the
conventions a change in that area has to respect.

- [**Graph rendering**](graph-rendering.md) — the layered layout engine:
  its pipeline and SVG rendering. Shared infrastructure, used by every
  visualization that wants layered geometry.
- [**Visualization switching**](visualization-switching.md) — how the
  app holds several visualizations of the dependency graph and selects
  one per request, and where the line between shared and
  per-visualization falls.
- [**Orbital dependency-weighted graph**](orbital-dependency-weighted-graph.md)
  — the dependency graph unfolded into a forest of radial trees, one per
  head, replicating a shared dependency into every work stream that
  waits on it so that the drawing contains no crossing edges at all.
  For what it draws day to day rather than how it is designed, see
  [`../development/visualizations/orbital.md`](../development/visualizations/orbital.md).

## How this differs from the other two doc directories

The repo has three, and the distinction is worth keeping sharp:

| Directory | Answers | Tense |
|---|---|---|
| [`../development/`](../development/) | "How do I work on this?" — setup, running the app, the test suites, CI, conventions, labels | What is true **now** |
| `architecture/` (here) | "How is this designed, and what must I not break?" — structure, contracts, invariants | The design, whether or not all of it is **built yet** |
| [`../solution-proposals/`](../solution-proposals/) | "Why was it done this way, and what was rejected?" | Frozen at the **date on it** |

The practical difference between the first two is that a doc here may
describe a design that is only partly implemented, as long as it says so
plainly and shows which parts exist. `development/` may not: if
something is described there, it is supposed to be true today.

That is the whole reason this directory exists. Work large enough to
span many changes needs a stable reference *while it is being built* —
otherwise each change re-derives the design from a solution proposal,
which is explicitly a point-in-time record and not a live source of
truth.

**A doc here doesn't graduate to `development/` when the work lands.**
It stays put — the module map and contracts are just as useful after
shipping, and they are a different kind of document from "how to run the
E2E suite".

## A known inconsistency

Several docs that are arguably architecture already live under
`development/` — `backend/routing.md`, `backend/containers.md`,
`backend/database-schema.md`, `ui/components.md`. They predate this
directory and have **not** been moved: they describe things that are
fully built, so they are not wrong where they are, and a bulk migration
would churn every inbound link for no reader benefit.

New architecture-level docs belong here. Whether the existing ones
eventually follow is an open question, not an oversight.
