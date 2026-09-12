# Components: `#container` and `#view`

There are two conventional root elements in this app, and they solve
different problems. Neither is a component system in the JS-framework
sense — they're just two `id`s that the routing and swap conventions are
built around.

## `#container` — the page shell

Defined once, in `Domain.Central.Responder.Ui.IndexView.indexTemplate`,
which is the *only* full HTML document (`<html>`/`<head>`/`<body>`) the
server ever renders:

```haskell
body_ $ do
  div_
    [ id_        "container"
    , hxGet_     lnk
    , hxTrigger_ "load"
    , hxReplaceUrl_ True
    , hxSwap_    "innerHTML"
    ] empty
```

`#container` starts empty. As soon as it loads, htmx fires a `GET` back
to whatever path the browser actually asked for (`lnk`, derived from the
request path + query string), and swaps the response's HTML into itself.
So **every page load is two round trips**: an empty shell, then the real
content. This is what makes the app behave like an SPA without being one
— `<head>` (global stylesheets, htmx and hyperscript) is only ever
loaded once, and every subsequent navigation targets `#container`
(`hxTarget_ "#container"`, `hxSwap_ "innerHTML"`) instead of a full page
load.

`global.css` pins its layout:

```css
#container {
  height: 100%;
  width: 100vw;
  overflow: hidden;
}
```

`overflow: hidden` here is deliberate and permanent: `#container` is
what keeps the shell pinned to the viewport rather than growing with
whatever page is currently swapped into it. That means it can never be
where a tall page scrolls from — see `#view`, below, for where that
actually lives.

## `#view` — a page's own root

Every top-level page template renders its own `<div id="view">` as the
first thing inside itself, e.g.:

| Module | Page |
|---|---|
| `ProjectIndex/View.hs` | Projects list page |
| `ProjectCreate/View.hs` | Add-project form |
| `ProjectManage/View.hs` | Manage-project (graph) page |
| `ProjectIndex/List.hs` | The project cards fragment (see below) |

This is the convention to follow for a new page: one `<div id="view">` as
your template's outermost element, after the nav header and any
page-specific `<link rel="stylesheet">` (see [styles.md](styles.md)).

`#view` also owns each page's scroll region: `global.css` sets
`overflow-y: auto` here, since `#container` above never can (see
`#container`, above). Something in the ancestor chain has to scroll, or
a page taller than the viewport is clipped by `#container`'s
`overflow: hidden` with no user-facing way to reach the rest — only
`#container.scrollTop = ...` from a script, which `overflow: hidden`
still permits but no real user has a path to.

A page whose own content must not scroll natively opts out in its own
scoped stylesheet — the dependency graph does this in
`views/manage-project.css`, because its viewport pans by transform on
`#graph-zoom-layer` and a scrollbar on `#view` behind it would be a
second, fighting way to move the same content.

## The swap hierarchy isn't flat

`#container` is the coarsest swap target, but pages load their own
sub-fragments independently, at finer granularity:

- `ProjectIndex/View.hs` renders `#view` containing a bare `<div>` that
  itself htmx-loads (`hxTrigger_ "load"`) the project cards from
  `ProjectIndex/List.hs`'s `templateList` — a second, nested round trip
  inside the page that's already inside `#container`'s round trip.
- The dependency graph (`ProjectManage/Graph.hs`) targets `#node-panel`
  directly when a node is clicked, and individual node labels target
  their own `#node-text-<id>` when refreshed — neither touches `#view` or
  `#container` at all.
- The toolbar's Stats button targets `#stats-body` inside the
  `#stats-panel` drawer, fetching `/ui/project/stats` on the same click
  that slides the drawer open. Counts move whenever a node's status
  does, so the drawer is filled per opening rather than once on load —
  and its own open/shut state is a class toggled in hyperscript, which
  needs no round trip at all.

So in practice there are (at least) three swap granularities in play:
whole page (`#container`), a page's own lazily-loaded sections (plain
`hxTrigger_ "load"` divs inside `#view`), and individual widgets
(`#node-panel`, `#node-text-<id>`, etc.). When adding a new interaction,
target the narrowest element that actually needs to change — that's the
existing convention throughout `ProjectManage/`.

## The node panel is anchored, not docked

`#node-panel` is a floating window over the graph, positioned against
the node it describes rather than parked in a corner: below it, flipping
above when there is no room underneath, and taking the roomier side when
neither fits. It never covers its own node — on a canvas too short for
it, the panel is capped to the room on its side and scrolls instead.
Closed is *empty* — htmx swaps its innerHTML in and out, and
`#node-panel:empty` takes it out of the layout entirely so an invisible
overlay cannot swallow drags meant for the graph.

Where it lands is measured at run time, because the node is a shape
inside a pannable SVG and "next to that shape" is not something CSS can
state. That measuring is hyperscript — `anchorBehavior` in
`ProjectManage/Node.hs`, emitted onto the panel's own body next to the
node id it anchors to — and it re-places whenever the viewport announces
a move or the panel's contents change height. It sets `left`, `top` and
`max-height`; everything else about the panel stays in the stylesheet.

The panel body emits `data-node-id`, and the selector that finds the
shape is **scoped to `#tree-container`** on purpose: the panel carries
the same attribute, and an unscoped selector lets the panel measure
itself instead of the node it is pointing at. Orbital draws one node
once per work stream, so that selector can match several shapes;
`anchorBehavior` measures `the first` explicitly, because hyperscript's
`measure` takes a single element and errors at runtime on a collection.

Hyperscript does not rank its operators, so every arithmetic expression
in `anchorBehavior` is parenthesised — mixing `+` and `/` without
brackets is a parse error there, not a precedence surprise.

## The node panel's fields

Every field in `#node-panel` is laid out the same way whether it is
being read or edited: its name above its value, the name set small,
muted and in caps so the value is what the eye lands on, and one
rhythm of space between fields. The panel is narrow and stacked, which
is what makes a name-beside-value form read as ragged in it.

Two things there that are alignment decisions rather than decoration:

- **The read-only properties are two columns**, a fixed name column and
  a value column, so `active` and `work` start at the same place down
  the panel. Spreading each row's name and value to opposite edges
  instead leaves every value at a different x, decided by how long its
  name happened to be.
- **The save-indicator slot keeps its size when it is empty.** A tick
  arriving mid-edit would otherwise change its label row's height and
  shunt every field below it down a line, in the middle of typing.

The panel's own two columns — the action rail and the detail beside it
— are sized by content and remainder rather than by percentages that
have to be kept adding up.

## Two floating panels, positioned differently

`#node-panel` is anchored to a node (above). `#add-work-panel` is not,
and deliberately: it is the panel for work that does not exist yet, so
there is no shape on the canvas for it to point at. It takes a fixed
corner instead, directly under the `+ Add work` control that opens it,
which is itself floated over the canvas rather than placed in the
toolbar beside Back and Stats — adding work is an action on *this*
drawing, and it belongs where the drawing is.

Both share the same closed state: empty, not hidden. htmx swaps each
one's innerHTML in and out, and `:empty` takes it out of the layout
entirely, so an invisible overlay cannot keep its corner of the canvas
and swallow drags meant for the graph.

See [htmx.md](../frontend/htmx.md) (once it lands) for the attribute
helpers themselves.
