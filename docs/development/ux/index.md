# UX

Where the design material this app's UI work is guided by lives, what it
is, and how much authority it has.

## `design/` — the mockups

`design/` at the repository root holds interactive HTML mockups, one
subdirectory per design effort, named for the effort and numbered:

```
design/
  project-manage-001/
    design_standalone.html
```

These are **committed to the repository**, mockup and all, so a clone
has them: every issue in a UI epic points at one by path, and reference
material only one machine has is not reference material. One file of a
few hundred KB is a price worth paying for that. Adding a mockup means
adding its directory here and committing it.

Each mockup is a **single self-contained HTML file**. It opens in a
browser with no server, no build step and no dependency on this app —
buttons work, panels open, state changes. That is the point of it: a
still image cannot show what happens when you click the thing, and a
description of what happens when you click the thing is exactly the part
that gets read three different ways.

They are Claude-generated, from a conversation about what a view should
do. The generated markup is a **wireframe made real enough to click**,
not a component library: inline styles, hardcoded fixture data, its own
little state machine in a `<script>`. None of that is a recommendation
about how to build it.

## What a mockup is for, and what it is not

**It is reference material.** Read it for intent — what is on the
screen, what is next to what, what opens what, what the flow is when a
user actually uses it. An issue that says "mirroring the mockup's stats
panel" means that.

**It is not a source of truth for implementation.** Where a mockup's own
details conflict with this repo's conventions, the conventions win,
every time:

| The mockup does | This app does |
|---|---|
| Inline `style="..."` on every element | Class names, styled in `global.css` or a per-view stylesheet — see [`ui/styles.md`](../ui/styles.md) |
| A client-side state machine in `<script>` | Server-rendered fragments swapped by htmx, with hyperscript for small effects — see [`frontend/`](../frontend/) |
| Hardcoded fixture objects | Real rows, queried in a responder |
| Its own colour literals | The tokens in [`ui/design-system.md`](../ui/design-system.md) |

So "the mockup uses a 300px panel with `#1f1f23`" is not a spec. "The
stats panel is a drawer against the right edge that does not push the
canvas" is.

**It is not shipped.** Nothing in `design/` is served, linked to, or
built. It is not the app's own HTML and no part of it is imported.

**It is not maintained against the app.** A mockup records what was
wanted at the time it was drawn. Once the work lands, the app is the
answer to what the app does, and `development/` is the answer to how —
the mockup is not updated to match, and a difference between the two is
not automatically a bug. Check the issue.

## Adding one

A new design effort gets a new subdirectory, numbered after the last:
`design/<effort>-<nnn>/`. Keep the mockup self-contained — a file that
needs a build step or a network fetch to open stops being the thing
anyone can just look at.
