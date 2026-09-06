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

So in practice there are (at least) three swap granularities in play:
whole page (`#container`), a page's own lazily-loaded sections (plain
`hxTrigger_ "load"` divs inside `#view`), and individual widgets
(`#node-panel`, `#node-text-<id>`, etc.). When adding a new interaction,
target the narrowest element that actually needs to change — that's the
existing convention throughout `ProjectManage/`.

See [htmx.md](../frontend/htmx.md) (once it lands) for the attribute
helpers themselves.
