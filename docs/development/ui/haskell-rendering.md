# UI implemented directly in Haskell

There is no template language and no template files. A "page" is a plain
Haskell function that returns `Html ()` (from [Lucid](https://hackage.haskell.org/package/lucid)),
built with do-notation combinators, and rendered to bytes at the very end
of a request handler.

## The basic shape

```haskell
projectIndexVwTemplate :: Html ()
projectIndexVwTemplate = do
    templateNavHeader "Projects"
    div_ [id_ "view"] $ do
      button_
        [ class_     "action-button"
        , hxGet_     "/ui/create-project/vw"
        , hxPushUrl_ True
        , hxTarget_  "#container"
        , hxSwap_    "innerHTML"
        ] "Create Project"
      ...
```

`div_`, `button_`, `class_`, etc. are ordinary functions — `class_ "x"` is
an `Attributes` value, `div_ [attrs] body` is a `Term`. There's nothing
Haskell-specific to learn beyond Lucid's own API; the point is that
building HTML is just building a value, so it composes, takes arguments,
and pattern-matches like any other Haskell code (see the `unless (null
errs) $ ...` in `ProjectCreate/View.hs` for a template branching on
validation errors).

The convention is one module per page/feature under
`responder/ui/<Feature>/`, usually named `View.hs`, exposing:

- a WAI handler (`handleProjectCreateVw`, `handleGetNodeRefresh`, ...)
  that does I/O (DB queries, request parsing) and eventually calls
  `renderBS` on a template value to produce the response body, and
- a pure template function (`projectCreateVwTemplate`, `templateRefresh`,
  ...) that only knows how to turn already-fetched data into `Html ()`.

Keeping those separate means the HTML-shape logic doesn't depend on WAI
or the database at all.

## Escaping Lucid's built-in vocabulary

Lucid ships combinators for standard HTML5, which isn't enough for htmx
attributes, hyperscript, or SVG. Two small local modules extend it via
Lucid's own escape hatches (`Lucid.Base`):

- **`Common.Web.Attributes`** — arbitrary attributes via `makeAttributes`:
  htmx's `hx-*` family (`hxGet_`, `hxSwap_`, `hxTarget_`, ...), hyperscript's
  `_` attribute (`h_`), and SVG attributes Lucid doesn't cover
  (`stroke_`, `strokeWidth_`, `markerEnd_`, `viewBox_`, ...). There are
  two variants for htmx's boolean attributes, e.g. `hxPushUrl_ :: Bool ->
  Attributes` (renders `"true"`/`"false"`) vs. `hxPushUrl'_ :: Text ->
  Attributes` for when the value itself needs to be a dynamic string.
  `hxVals_`/`hxVals'_` encode a Haskell value as the JSON `hx-vals`
  htmx expects.
- **`Common.Web.Elements`** — arbitrary elements via `term`, for the SVG
  tags Lucid has no combinator for: `rect_`, `path_`, `g_`, `marker_`,
  `defs_`, `text_`, `tspan_`, plus `circle_` and `line_`, which nothing
  currently uses. Used exclusively by the dependency-graph template
  (`ProjectManage/Graph.hs`).

If you need an attribute or element that isn't already in one of these
two modules, add it there rather than reaching for a raw string
elsewhere — that's the established extension point.

## Passing server data to client JS

**There is no longer a pattern for this in the app, which is the point.**

The dependency graph used to embed its data as JSON in a
`<script id="graph-data" type="application/json">` for `nodetree2.js` to
read and lay out. That whole approach is gone: the
server now computes every coordinate and sends finished SVG, so the
graph's data never reaches the browser at all. See
[`../../architecture/graph-rendering.md`](../../architecture/graph-rendering.md).

What remains is a much smaller need — handing a script a few scalars
about something the server already computed. The graph viewport does it
with `data-*` attributes on the element itself:

```haskell
svg_
  [ id_ "tree-view"
  , dataBaseWidth_ (dblText w)   -- natural size, for zoom
  , dataRootX_ (dblText rootX)   -- where to scroll on open
  , ...
  ]
```

`graph-viewport.js` reads them off `svg.dataset`. Prefer this to
embedding JSON: it keeps the values next to the element they describe,
it needs no parsing, and it doesn't tempt anyone into moving real logic
back to the client. If you genuinely need structured data client-side,
that's a design question worth raising rather than a pattern to copy.

## Forms

Forms are plain `form_`/`input_`/`textarea_`, but submit via
`hxPost_`/`hxPut_` instead of a native form POST, so the response can be
swapped in-place instead of navigating (e.g. `ProjectCreate/View.hs`'s
`form_ [..., hxPost_ "/ui/create-project/submit"]`). There is no
client-side form-handling JS to write for this — htmx handles serializing
the form and firing the request.
