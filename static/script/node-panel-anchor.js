// Places the node detail panel against the node it belongs to.
//
// The panel is an ordinary absolutely-positioned element inside #view,
// but the node it points at lives in an SVG the user can pan and zoom.
// Nothing in CSS can express "next to that shape", so the position is
// measured here and handed back as two custom properties -- everything
// about how the panel *looks* stays in manage-project.css, which is the
// same split the graph itself keeps.
//
// Measuring is deliberately getBoundingClientRect rather than the
// layout's own coordinates put through the zoom transform. The rect is
// already in screen pixels whatever the transform is doing, which keeps
// this file from having to know that a transform exists at all -- and
// means it still works on the fallback path where d3 never loaded.
//
// This loads with the Manage Project view rather than app-wide, and
// re-runs whenever that view is swapped in again, so it tears down the
// previous run the way graph-viewport.js does.
(() => {
  const view = document.getElementById("view");
  const panel = document.getElementById("node-panel");
  const canvas = document.getElementById("tree-container");
  if (!view || !panel || !canvas) return;

  if (window._nodePanelAnchorTeardown) window._nodePanelAnchorTeardown();

  // Clear air between the node's edge and the panel, and the smallest
  // gap the panel will keep from the edge of the canvas.
  const GAP = 14;
  const MARGIN = 12;
  // The floor the height cap will not go under. Below this the panel is
  // too short to read anything in, and covering part of the node is the
  // better of two bad answers.
  const MIN_HEIGHT = 120;

  const ac = new AbortController();
  const signal = ac.signal;

  const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), Math.max(lo, hi));

  // The shape the open panel belongs to. Orbital draws one node once
  // per work stream, so several shapes can carry the same id -- the
  // panel anchors to whichever replica is nearest the middle of the
  // canvas, which is the one the user is most likely looking at.
  const anchorRect = () => {
    const marker = panel.querySelector("[data-node-id]");
    if (!marker) return null;
    const shapes = canvas.querySelectorAll(
      `[data-node-id="${CSS.escape(marker.dataset.nodeId)}"]`
    );
    const frame = canvas.getBoundingClientRect();
    const cx = frame.left + frame.width / 2;
    const cy = frame.top + frame.height / 2;

    let best = null;
    let bestDistance = Infinity;
    for (const shape of shapes) {
      const r = shape.getBoundingClientRect();
      const d = Math.hypot(
        r.left + r.width / 2 - cx,
        r.top + r.height / 2 - cy
      );
      if (d < bestDistance) {
        bestDistance = d;
        best = r;
      }
    }
    return best;
  };

  const place = () => {
    // Closed is empty, not hidden: an empty panel has nothing to
    // anchor and takes no box to place.
    if (!panel.firstElementChild) return;
    const node = anchorRect();
    if (!node) return;

    const frame = view.getBoundingClientRect();

    // Measured with any previous run's cap lifted, so what comes back
    // is the height the contents actually want rather than the height
    // some earlier node's surroundings allowed.
    panel.style.removeProperty("--panel-max-height");
    const size = panel.getBoundingClientRect();

    const roomBelow = Math.max(0, frame.bottom - MARGIN - (node.bottom + GAP));
    const roomAbove = Math.max(0, node.top - GAP - (frame.top + MARGIN));

    // Below the node by default, above it when the room underneath has
    // run out, and on the roomier side when it has run out on both.
    // That flip is the whole reason this is computed rather than fixed:
    // a node near the bottom edge would otherwise open a panel mostly
    // off the canvas.
    const fitsBelow = roomBelow >= size.height;
    const fitsAbove = roomAbove >= size.height;
    const below = fitsBelow || (!fitsAbove && roomBelow >= roomAbove);

    // The panel gives up height rather than ground. A tall panel on a
    // short canvas fits nowhere, and left to clamp itself into view it
    // would settle directly over the node it is describing -- pointing
    // at something it is covering. Capping it to the room on its chosen
    // side keeps that from happening; the panel already scrolls, so the
    // cost is a scrollbar rather than a hidden node.
    const room = Math.max(MIN_HEIGHT, below ? roomBelow : roomAbove);
    panel.style.setProperty("--panel-max-height", `${Math.floor(room)}px`);
    const height = Math.min(size.height, room);

    const top = below ? node.bottom + GAP : node.top - GAP - height;
    const left = node.left + node.width / 2 - size.width / 2;

    // Horizontal is still a clamp, so a node panned half out of view
    // gets a readable panel rather than one trailing off the edge after
    // it. Vertical is already inside the frame by construction; the
    // clamp there is a floor under the arithmetic, not a placement.
    const x = clamp(left, frame.left + MARGIN, frame.right - MARGIN - size.width);
    const y = clamp(top, frame.top + MARGIN, frame.bottom - MARGIN - height);

    panel.style.setProperty("--panel-left", `${Math.round(x - frame.left)}px`);
    panel.style.setProperty("--panel-top", `${Math.round(y - frame.top)}px`);
  };

  // A pan writes a transform per frame, and each one would otherwise
  // cost a forced layout to measure against. One placement per frame is
  // enough for the panel to look attached.
  let frameRequest = null;
  const schedulePlace = () => {
    if (frameRequest !== null) return;
    frameRequest = requestAnimationFrame(() => {
      frameRequest = null;
      place();
    });
  };

  // Both the panel opening and its inner detail/edit swaps change what
  // there is to place: the first picks a new node, the second changes
  // the height the flip is decided from. The inner swaps target
  // #node-detail and bubble up to here.
  panel.addEventListener("htmx:afterSwap", schedulePlace, { signal });

  // The graph moving under the panel. Watching the attribute rather
  // than subscribing to d3 keeps this independent of how the transform
  // got there, and the subtree is watched rather than the zoom layer
  // itself because that layer is replaced on every graph load while
  // #tree-container survives.
  const observer = new MutationObserver(schedulePlace);
  observer.observe(canvas, {
    attributes: true,
    attributeFilter: ["transform"],
    childList: true,
    subtree: true,
  });

  window.addEventListener("resize", schedulePlace, { signal });

  window._nodePanelAnchorTeardown = () => {
    if (frameRequest !== null) cancelAnimationFrame(frameRequest);
    observer.disconnect();
    ac.abort();
  };

  schedulePlace();
})();
