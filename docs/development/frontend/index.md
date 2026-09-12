# Client-Side Interactivity

## How much JavaScript belongs here

**As little as possible.** Application behaviour is Haskell, htmx and
hyperscript; a `.js` file is the last resort, not the first.

Where a real script is unavoidable — the graph viewport needs `d3-zoom`
for gestures, and that is not a hyperscript one-liner — it is held to a
narrow job and made to **announce, not decide**:

- It owns its own concern and nothing else. `graph-viewport.js` owns one
  SVG transform. It does not know the app has URLs.
- Anything it learns leaves as a **generic DOM event** (`graph:viewport`),
  so what that means is decided outside it.
- Anything it needs to be *told* arrives as **server-rendered data
  attributes**, the same way the layout's own coordinates do — not by
  the script reading the query string itself.

The payoff is that effects beyond the script's purpose live where the
rest of the app's behaviour lives, and can be changed without touching
a bundle. Mirroring the viewport into the URL is a hyperscript
behaviour on `#tree-container`, written in Haskell next to the element
it is attached to.

Three JS libraries are loaded (all from `IndexView.hs`'s `<head>`), each
doing a distinct job:

- [**HTMX**](htmx.md) — page navigation and in-page updates, driven by
  `hx-*` attributes emitted from Haskell. This is the one doing the
  actual work of turning server-rendered fragments into an SPA-feeling
  app; see [`../ui/components.md`](../ui/components.md) for the
  `#container`/`#view` elements it swaps.
- [**hyperscript**](hyperscript.md) — small, declarative, per-element
  visual effects (`_`/`h_` attribute) that don't need real JS.
- **`graph-viewport.js`** (`static/script/`) — pan and zoom for the
  dependency graph, driven by `d3-zoom`. It does *not* lay the
  graph out: the server sends finished SVG with every coordinate already
  computed (see
  [`../../architecture/graph-rendering.md`](../../architecture/graph-rendering.md)),
  and this script only writes a `transform` onto the `#graph-zoom-layer`
  group inside it.

  **On d3 being here at all.** If you are looking for graph layout code
  on the client, there isn't any — it's Haskell. `d3-zoom` is narrow
  enough to earn its place, on two conditions that both hold:

  - *It was doing layout.* This isn't. `d3-zoom` is a gesture library
    here — it moves one transform and never reads the graph's
    structure. No graph data is sent to the browser.
  - *It loaded on every page.* This doesn't. `static/script/vendor/`
    `d3-graph-zoom.js` (~47KB, `d3-selection` + `d3-zoom` only) is
    pulled in by a dynamic `import()` inside `graph-viewport.js`, which
    only the graph fragment loads. Every other page in the app fetches
    no d3 at all.

  Gestures: drag or plain wheel to pan, ctrl/cmd+wheel (a trackpad
  pinch) to zoom, double-click to reset, and arrows/`+`/`−`/`0` from
  the keyboard. There are deliberately no on-screen zoom buttons — see
  [Viewport](../../architecture/graph-rendering.md#viewport).

  **It has no idea a query string exists.** Where the view came from
  and what should be recorded about it are both somebody else's
  business:

  - the view a request asked for arrives as `data-view-x` /
    `data-view-y` / `data-view-scale` on `#tree-container`, parsed
    server-side in `ProjectManage/View.hs` alongside `projectId` and
    `visualizationMode`;
  - the current view leaves as a `graph:viewport` DOM event carrying
    `{x, y, k, adjusted}`;
  - and the one signal coming back the other way is `graph:reveal`,
    a `{nodeId}` sent to `#tree-container` by whatever has decided that
    node matters. The view then moves the least it can to put that node
    on screen — see [components.md](../ui/components.md)'s "A selected
    node is brought into view".

  The hyperscript on `#tree-container` (`viewUrlBehavior`) turns that
  event into the address bar: a view the user has moved is spelled out
  as `viewX`/`viewY`/`viewScale`, so reload and a shared link return to
  it, and a view still at its opening position is left out so a reset
  gives back the plain URL. It appends to `data-view-base` — the same
  URL with the view parameters removed, rendered server-side — rather
  than editing the current URL in place, which keeps hyperscript out of
  query-string parsing entirely.
