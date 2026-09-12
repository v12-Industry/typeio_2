# HTMX

[htmx](https://htmx.org) is how every page navigation and most in-page
updates happen — it's loaded once (`static/script/htmx.js`, linked in
`IndexView.hs`) and driven entirely by `hx-*` attributes emitted from
Lucid, via the small wrapper in `Common.Web.Attributes`
(`hxGet_`, `hxPost_`, `hxPut_`, `hxSwap_`, `hxTarget_`, `hxTrigger_`,
`hxPushUrl_`/`hxPushUrl'_`, `hxReplaceUrl_`, `hxInclude_`, `hxIndicator_`,
`hxSync_`, `hxVals_`/`hxVals'_`). There's no client-side JS to write for
any of the patterns below.

See [components.md](../ui/components.md) for the `#container`/`#view`
elements these patterns target.

## Pattern: full-page navigation

```haskell
button_
  [ class_     "action-button"
  , hxGet_     "/ui/create-project/vw"
  , hxPushUrl_ True
  , hxTarget_  "#container"
  , hxSwap_    "innerHTML"
  ] "Create Project"
```

`hxTarget_ "#container"` + `hxSwap_ "innerHTML"` + `hxPushUrl_ True` is
the "this behaves like a page navigation" recipe used throughout —
project cards (`ProjectIndex/List.hs`), the nav header's logo
(`MainHeader.hs`), etc. all follow it.

## Pattern: lazy-load a fragment on mount

```haskell
div_
  [ hxGet_     "/ui/projects/list"
  , hxPushUrl_ False
  , hxTrigger_ "load"
  , hxSwap_    "innerHTML"
  ] mempty
```

No `hxTarget_` — htmx defaults to targeting the triggering element
itself, so the empty `div_` becomes the project list once its response
comes back. `#container`'s own initial load in `IndexView.hs` is the same
pattern one level up. Use this for a section of a page that needs its own
data but shouldn't block the rest of the page rendering first.

## Pattern: inline-edit autosave

The node-edit fields (`ProjectManage/Node/Edit.hs`) PUT on every change,
debounced, targeting a small status indicator rather than the whole form:

```haskell
input_ [ ...
       , hxPut_     "/ui/project/node/title"
       , hxPushUrl_ False
       , hxInclude_ "this"
       , hxTrigger_ "input changed delay:500ms"
       , hxVals'_ $ object
           [ "projectId" .= (intToText . fromSqlKey . M.nodeProjectId $ nde)
           , "nodeId"    .= (intToText . fromSqlKey $ k)
           ]
       , hxTarget_ "label[for=\"title\"] .indicator-box"
       ]
```

Worth noting on this one:

- `hxTrigger_ "input changed delay:500ms"` is htmx's debounce — fires
  500ms after typing stops, not on every keystroke.
- `hxInclude_ "this"` scopes the request to just this field's own value,
  since these inputs aren't wrapped in a `<form>`.
- `hxVals'_` attaches extra JSON (`projectId`/`nodeId`) the endpoint
  needs but that isn't itself a form field — see `Common.Web.Attributes`'
  `hxVals_`/`hxVals'_` for the two ways to build that JSON from Haskell.
- `hxTarget_` here is a **CSS selector**, not just an `id` — htmx accepts
  either, and this codebase uses both depending on how specific the
  target needs to be.

The PUT endpoints these hit (`/ui/project/node/title`, `/description`,
`/status`) exist specifically to be called this way — they're not a
general-purpose REST API, they're autosave hooks for one field each.

## Pattern: event-driven triggers

`ProjectManage/Graph.hs`'s node labels listen for a custom event rather
than a user action:

```haskell
hxTrigger_ $ "nodePanel:onEditClosed[event.detail.nodeId=="
             <> (intToText . graphNodeId $ n)
             <> "] from:#node-panel"
```

This fires when something dispatches a `nodePanel:onEditClosed` DOM
event on `#node-panel` whose `event.detail.nodeId` matches this
particular node — i.e. "refresh my own text once the edit panel for *me
specifically* closes," filtering out edits to other nodes. If you're
extending this, trace where `nodePanel:onEditClosed` actually gets
dispatched before assuming — it isn't in `Graph.hs` itself.

## Pattern: one response that changes two places

The "Add work" panel's submit
(`ProjectManage/Node/Create.hs`) has three things to do at once: close
the panel that submitted it, open the new node's own panel, and get the
drawing redrawn with the node in it. It does all three from one
response, with no client-side code:

- **The form's own target is the panel it lives in**, so whatever comes
  back is what the person is left looking at. A rejected title returns
  the form again, complaint included, still open. A success returns
  nothing for that target — and `#add-work-panel:empty` is its closed
  state, so the panel closes by being emptied.
- **The node panel is swapped out of band**: the response carries a
  `<div id="node-panel" hx-swap-oob="innerHTML">` (`hxSwapOob_`), which
  htmx lifts out and applies by id rather than to the target.
- **The graph is told to refetch** by an `HX-Trigger: nodeCreated`
  response header, which htmx turns into a DOM event on `body`;
  `#tree-container` listens for it (`hx-trigger="load, nodeCreated from:
  body"`) and re-fetches the graph fragment. The drawing is rendered
  server-side, so this refetch is the only thing that puts a new node on
  screen.

Worth knowing when adding a fourth thing: an out-of-band fragment must
carry the **id of the element it is replacing**, not the id of anything
in the response's own target, and `hx-swap-oob="innerHTML"` swaps the
fragment's *children* into that element.

## Debugging

`hxIndicator_`/`hxSync_` exist in `Common.Web.Attributes` but aren't
exercised by the examples above — check htmx's own docs for those if you
need a loading indicator or to coordinate overlapping requests on one
element.
