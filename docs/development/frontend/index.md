# Client-Side Interactivity

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
