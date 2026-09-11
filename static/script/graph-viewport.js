// Pan-and-zoom viewport for the server-rendered dependency graph,
// driven by d3-zoom.
//
// The graph is laid out entirely server-side: d3 here is a *gesture*
// library, not a layout one. It writes a single `transform` onto
// #graph-zoom-layer and never looks at the graph's structure, so the
// "no client-side layout code, no graph data sent to the browser" rule
// in docs/architecture/graph-rendering.md holds.
//
// Panning by transform rather than by scrolling the container is what
// makes the gesture set below sufficient on its own: a transform-based
// viewport gets its whole reach from ordinary canvas gestures, so there
// is no on-screen +/- or recentre button cluster to maintain.
//
// Gestures:
//   drag                 pan
//   wheel / two-finger   pan
//   ctrl or cmd + wheel  zoom (this is also what a trackpad pinch
//                        reports as, so one handler covers both)
//   double-click         reset to the opening view
//   arrow keys           pan          (keyboard equivalent, since
//   + / - / 0            zoom, reset   there are no buttons)
//
// The transform is also mirrored into the URL's query string, so a
// reload or a back/forward lands on the view the user had open rather
// than back at the project root. See `syncUrl` for the shape of that
// and for why only an adjusted view is written.
//
// d3 is loaded only from here, and this file is loaded only by the
// graph fragment -- see the note on the <script> tag in Graph.hs. That
// scoping is the point: this bundle is ~47KB and arrives only with a
// graph, never app-wide.
//
// This file is loaded by the graph fragment itself, so it re-runs on
// every htmx swap into #tree-container. Everything below is written to
// be idempotent under that: see `teardown`.
(() => {
  const container = document.getElementById("tree-container");
  const svg = document.getElementById("tree-view");
  const layer = document.getElementById("graph-zoom-layer");
  if (!container || !svg || !layer) return;

  // The fragment is swapped in repeatedly and #tree-container survives
  // each swap, so listeners bound to it would otherwise accumulate one
  // set per swap. Each run tears the previous run's down first.
  if (container._graphViewportTeardown) container._graphViewportTeardown();

  const ac = new AbortController();
  const signal = ac.signal;
  // Set before the dynamic import resolves: a fast second swap can tear
  // this run down while the import is still in flight, and the halves
  // that have not been set up yet must not be set up afterwards.
  let disposed = false;
  container._graphViewportTeardown = () => {
    disposed = true;
    ac.abort();
  };

  const num = (name, fallback) => {
    const v = parseFloat(svg.dataset[name]);
    return Number.isFinite(v) ? v : fallback;
  };

  // Natural size and root position, from the layout engine's own
  // bounds. The server placed the root and emits where it landed, so
  // the client never has to hunt the DOM for it.
  const baseWidth = num("baseWidth", 1);
  const baseHeight = num("baseHeight", 1);
  const rootX = num("rootX", baseWidth / 2);
  const rootY = num("rootY", baseHeight / 2);

  // The transform's three numbers, as query params. Named in the same
  // camelCase as every other param the app reads (`projectId`,
  // `visualizationMode`), because they share the URL with them.
  const PARAM_X = "viewX";
  const PARAM_Y = "viewY";
  const PARAM_SCALE = "viewScale";
  // A pan emits a transform per frame. Rewriting the URL that often is
  // wasted work, so writes settle first.
  const URL_SYNC_DELAY = 200;

  const MIN_SCALE = 0.2;
  const MAX_SCALE = 3;
  const KEY_PAN_STEP = 60; // px per arrow key press
  const KEY_ZOOM_STEP = 1.2;
  const DRAG_THRESHOLD = 4;

  // The bundle is ESM, so it loads via dynamic import from this classic
  // script rather than a <script type="module"> tag: a module executes
  // once per document no matter how many times its tag is swapped in,
  // which would break on the second graph load. The module is fetched
  // once and cached; this wrapper re-runs per swap.
  //
  // d3-selection and d3-zoom come from one bundle rather than two
  // deliberately -- see the header in that file; two copies of
  // d3-selection is a runtime failure, not just waste.
  import("/static/script/vendor/d3-graph-zoom.js")
    .then(({ select, pointer, zoom, zoomIdentity, zoomTransform }) => {
      if (disposed) return;

      const svgSel = select(svg);

      // Opening view: the project root centred at natural size. Note
      // this is deliberately not fit-to-screen -- a large project is
      // meant to overflow and be navigated, not shrunk until its titles
      // stop being readable.
      const openingTransform = () =>
        zoomIdentity
          .translate(
            container.clientWidth / 2 - rootX,
            container.clientHeight / 2 - rootY
          )
          .scale(1);

      let moved = false;
      let gestureStart = null;
      // Whether the view on screen is the user's or just the one it
      // opened at. Only the former is worth carrying in the URL: an
      // untouched view is better recomputed on arrival, because the
      // opening transform centres the root against the container's
      // current size and a window resized since would restore off
      // centre.
      let adjusted = false;
      let urlSyncTimer = null;

      const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

      const urlTransform = () => {
        const params = new URLSearchParams(window.location.search);
        const x = parseFloat(params.get(PARAM_X));
        const y = parseFloat(params.get(PARAM_Y));
        const k = parseFloat(params.get(PARAM_SCALE));
        if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(k)) {
          return null;
        }
        // A hand-edited or stale scale is clamped rather than refused:
        // the same extent the gestures are held to, so no URL can put
        // the graph somewhere the gestures cannot get back from.
        return zoomIdentity.translate(x, y).scale(clamp(k, MIN_SCALE, MAX_SCALE));
      };

      // Writes the current transform into the URL, or takes it back out
      // once the view is the opening one again -- a reset should leave
      // the plain URL the project was reached by, not a spelled-out
      // copy of the default.
      //
      // replaceState, never pushState: a pan is not a navigation, and a
      // history entry per gesture would bury the node the user actually
      // navigated to under a run of near-identical views.
      const syncUrl = () => {
        const url = new URL(window.location.href);
        if (adjusted) {
          const t = zoomTransform(svg);
          url.searchParams.set(PARAM_X, String(Number(t.x.toFixed(2))));
          url.searchParams.set(PARAM_Y, String(Number(t.y.toFixed(2))));
          url.searchParams.set(PARAM_SCALE, String(Number(t.k.toFixed(4))));
        } else {
          url.searchParams.delete(PARAM_X);
          url.searchParams.delete(PARAM_Y);
          url.searchParams.delete(PARAM_SCALE);
        }
        if (url.href === window.location.href) return;
        history.replaceState(history.state, "", url);
      };

      const scheduleUrlSync = () => {
        clearTimeout(urlSyncTimer);
        urlSyncTimer = setTimeout(syncUrl, URL_SYNC_DELAY);
      };

      const zb = zoom()
        .scaleExtent([MIN_SCALE, MAX_SCALE])
        // Left button only, and never start a gesture on the wheel --
        // the wheel is handled below so a plain scroll pans instead of
        // zooming. ctrl+click is a right-click on macOS, so it is not a
        // pan either.
        .filter((event) => {
          if (event.type === "wheel") return false;
          if (event.ctrlKey) return false;
          return event.button == null || event.button === 0;
        })
        .on("start", (event) => {
          moved = false;
          gestureStart = event.transform;
          if (event.sourceEvent) {
            container.classList.add("is-panning");
            adjusted = true;
          }
        })
        .on("zoom", (event) => {
          layer.setAttribute("transform", event.transform.toString());
          scheduleUrlSync();
          // A press only counts as a drag past DRAG_THRESHOLD pixels,
          // so a click with a pixel of hand-shake in it still opens the
          // node it landed on.
          if (gestureStart && !moved) {
            const dx = event.transform.x - gestureStart.x;
            const dy = event.transform.y - gestureStart.y;
            if (Math.hypot(dx, dy) > DRAG_THRESHOLD) moved = true;
          }
        })
        .on("end", () => {
          container.classList.remove("is-panning");
        });

      svgSel.call(zb);
      // d3-zoom's own wheel and double-click handlers are both
      // replaced: the wheel pans here rather than zooming, and a
      // double-click resets the view rather than zooming in.
      svgSel.on("wheel.zoom", null).on("dblclick.zoom", null);

      const currentScale = () => zoomTransform(svg).k;

      const reset = () => {
        adjusted = false;
        zb.transform(svgSel, openingTransform());
      };

      // --- Wheel: pan, or zoom with ctrl/cmd ---------------------------
      //
      // A trackpad pinch arrives as a wheel event with ctrlKey set, so
      // this one handler covers pinch-to-zoom as well. Bound directly
      // rather than through d3 so `passive: false` is unambiguous --
      // without it the preventDefault below is ignored and the page
      // scrolls behind the graph.
      svg.addEventListener(
        "wheel",
        (event) => {
          event.preventDefault();
          adjusted = true;
          if (event.ctrlKey || event.metaKey) {
            zb.scaleBy(
              svgSel,
              Math.exp(-event.deltaY * 0.002),
              pointer(event, svg)
            );
          } else {
            // translateBy works in the transformed space, so screen
            // pixels have to be divided back down by the current scale.
            const k = currentScale();
            zb.translateBy(svgSel, -event.deltaX / k, -event.deltaY / k);
          }
        },
        { passive: false, signal }
      );

      // --- Double-click resets ------------------------------------------
      svg.addEventListener(
        "dblclick",
        (event) => {
          event.preventDefault();
          reset();
        },
        { signal }
      );

      // --- Keyboard -----------------------------------------------------
      //
      // Not a nice-to-have: with the +/- buttons gone, this is the only
      // non-pointer way to move around the graph.
      container.addEventListener(
        "keydown",
        (event) => {
          if (event.metaKey || event.ctrlKey || event.altKey) return;
          const k = currentScale();
          // Marking the adjustment inside the movers rather than beside
          // the switch keeps it off the two keys that do not move the
          // view: an unhandled key, and `0`, whose `reset` clears it.
          const pan = (dx, dy) => {
            adjusted = true;
            zb.translateBy(svgSel, dx / k, dy / k);
          };
          const zoomBy = (factor) => {
            adjusted = true;
            zb.scaleBy(svgSel, factor);
          };
          switch (event.key) {
            case "ArrowLeft":
              pan(KEY_PAN_STEP, 0);
              break;
            case "ArrowRight":
              pan(-KEY_PAN_STEP, 0);
              break;
            case "ArrowUp":
              pan(0, KEY_PAN_STEP);
              break;
            case "ArrowDown":
              pan(0, -KEY_PAN_STEP);
              break;
            case "+":
            case "=":
              zoomBy(KEY_ZOOM_STEP);
              break;
            case "-":
            case "_":
              zoomBy(1 / KEY_ZOOM_STEP);
              break;
            case "0":
              reset();
              break;
            default:
              return;
          }
          event.preventDefault();
        },
        { signal }
      );

      // --- Drag must not read as a click --------------------------------
      //
      // Every node is also a click target (htmx opens its detail
      // panel), so the click the browser fires after a pan has to be
      // swallowed -- exactly once, in the capture phase, before it
      // reaches the node's handler.
      container.addEventListener(
        "click",
        (event) => {
          if (!moved) return;
          moved = false;
          event.stopPropagation();
          event.preventDefault();
        },
        { capture: true, signal }
      );

      // --- The URL is the other end of the transform ---------------------
      //
      // Opening a node pushes a URL of its own, which arrives without
      // these params. Restamping the settled view onto the entry htmx
      // just pushed is what keeps a reload after a click landing where
      // a reload after a gesture does.
      document.addEventListener("htmx:pushedIntoHistory", syncUrl, { signal });

      // Back and forward move between entries that each carry their own
      // view. Reading it here means the graph follows even when htmx
      // restores the page from its own cache rather than re-running
      // this script.
      window.addEventListener(
        "popstate",
        () => {
          const t = urlTransform();
          adjusted = t !== null;
          zb.transform(svgSel, t ?? openingTransform());
        },
        { signal }
      );

      // --- Start ---------------------------------------------------------
      // Deferred one frame: the fragment has just been swapped in, and
      // container.clientWidth/clientHeight are only meaningful once the
      // browser has laid it out. A view carried in the URL wins over the
      // opening one.
      requestAnimationFrame(() => {
        if (disposed) return;
        const t = urlTransform();
        adjusted = t !== null;
        zb.transform(svgSel, t ?? openingTransform());
      });

      // d3 binds its own listeners outside the AbortController, so they
      // are removed explicitly on top of aborting the signal.
      const abortSignalTeardown = container._graphViewportTeardown;
      container._graphViewportTeardown = () => {
        clearTimeout(urlSyncTimer);
        svgSel.on(".zoom", null);
        abortSignalTeardown();
      };
    })
    .catch((err) => {
      // A failed import must not leave the graph as an unreachable
      // window onto its own top-left corner. Falling back means undoing
      // the two things that make the transform viewport work: give the
      // SVG its natural size again, and let the container scroll. That
      // is the pre-d3 viewport minus its gestures -- degraded, but the
      // whole graph is still reachable.
      console.error("graph viewport: d3 failed to load", err);
      svg.setAttribute("width", String(baseWidth));
      svg.setAttribute("height", String(baseHeight));
      container.classList.add("viewport-fallback");
    });
})();
