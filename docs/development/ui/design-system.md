# Design System: Colors, Indicators, and Loading States

[Components](components.md) covers the `#container`/`#view` structural
pattern, and [Styles](styles.md) covers where a stylesheet belongs
(global vs. per-view). This doc covers what those two don't: the actual
visual tokens (`static/styles/global.css`'s `:root` block) and the
indicator/loading-state patterns built on top of them. Consolidates
what's already in `static/styles/` — no new conventions invented here.

## Color tokens

All defined once, in `global.css`'s `:root` block. Grouped here by
purpose (the source groups them the same way, via comments):

| Group | Tokens | Used for |
|---|---|---|
| Background | `--bg-start`, `--bg-end` | The `body` gradient (`linear-gradient(to bottom right, ...)`) |
| Text | `--text-primary`, `--text-secondary` | Primary body/label text vs. secondary/muted text (e.g. `.logo:hover`) |
| Accent | `--accent`, `--accent-light`, `--accent-bold`, `--accent-select` | Buttons, highlights, and the graph's node fills (`--accent-bold` for root nodes, `--accent-light` for work nodes) |
| Accent hover | `--accent-hover`, `--accent-hover-light`, `--accent-hover-bold` | Hover states paired 1:1 with the accent tokens above (e.g. `--accent-hover-bold` on `#tree-container .node .root:hover`) |
| Accent (semantic) | `--accent-success` | Defined alongside the accent family but currently unused anywhere — same "defined, not wired up" situation as `.pill-indicator` below |
| Borders | `--border-color` | Dividers, input backgrounds (`input`/`textarea` use it as their `background-color`, not as a border — worth knowing before assuming the name always matches the usage) |
| Status | `--error-color`, `--success` | Validation error backgrounds/messages, and the save-success checkmark icon color (`#node-detail i`) |
| Surface | `--surface` | Card backgrounds (`.card-grid > *`) — a semi-transparent accent (`#78a0ff14`, i.e. `#78a0ff` at low alpha) rather than a solid color, meant to sit over the body gradient with `backdrop-filter: blur(4px)` |

**Convention**: a color used by more than one class, or one that
represents a reusable concept (a status, an interaction state), belongs
here as a token — this mirrors `styles.md`'s "shared class → global"
rule, applied to colors specifically. Not universally followed today:
`.action-button` (`#e0e0e0`, `#999`), `#tree-container .link`'s stroke
(`#999`), and the graph nodes' `stroke: white` are all untokenized
literals. Documented as the current, inconsistent reality — not a
backlog item to silently fix as a drive-by change.

**A real bug found while writing this up, not a style question**:
`.logo`'s `background-color: var(--accent-color)` references a token
that was never defined anywhere in `:root` — the closest real token is
`--accent`. An undefined custom property falls back to the property's
initial value, so the "textio" wordmark currently renders with no
background at all, and it is tracked separately rather than fixed in a
docs change.

## Indicators

- **`.pill-button`** (and `.pill-button.selected`) — the pill-shaped
  *interactive* control: the node-panel's edit/save/close icon buttons
  (`Domain.Project.Responder.Ui.ProjectManage.Node.templateNodePanel`)
  and the status `<select>`'s styling. `.selected` marks whichever
  choice is currently active.
- **`.pill-indicator`** — a pill-shaped, *non-interactive* variant (no
  `cursor: pointer`, accent-colored border/text) defined in
  `global.css`. Checked across every `.hs` file in the app: **it's not
  referenced anywhere.** Documented here as dead CSS / a built-but-
  unused pattern rather than silently skipped, the same "resolve, don't
  leave dangling" bar this repo already applies elsewhere (e.g. the
  `wifi-password` investigation in
  [`../../solution-proposals/security-scanning.md`](../../solution-proposals/security-scanning.md)
  §2.2). Either a real use case shows up for it, or it's worth a cleanup
  ticket — not decided here.
- **`.indicator-label` / `.indicator-box`** — the per-field save-status
  pattern in the node-edit panel
  (`Domain.Project.Responder.Ui.ProjectManage.Node.Edit`'s Title/
  Description/Status sections). Each editable field's label pairs with
  a small `.indicator-box` slot; different states swap content into it
  via htmx's `hxTarget_`:
  - **Pending** — a `.loading` spinner (below), injected by hyperscript
    every 8th keystroke while typing (the title field's `on input
    increment my.icount if my.icount mod 8 === 0 then set
    #title-indicator's innerHTML to ...`) — deliberately not on every
    keystroke, to avoid spamming the DOM on fast typing.
  - **Success** — a checkmark (`<i class="material-icons">done</i>`),
    returned by the field's own `PUT` handler on save (e.g.
    `Node.Title.templatePostSuccess`).
  - **Error** — an error icon (`<i class="material-icons">error</i>`)
    plus the validation-message list, from the same handler's failure
    path (`Node.Title.templatePostFail`).
- **`.node-highlight`** (scoped to `#tree-container`, in
  `manage-project.css`) — a glow (`filter: drop-shadow(...)`) on the
  rounded rect for whichever node's detail panel is currently
  open. Not a class the server ever sets directly — hyperscript adds it
  when the panel opens and removes it on the panel's own htmx cleanup
  event (`templateNodePanel`'s `on load add .node-highlight to #node-<id>
  on htmx:beforeCleanupElement remove .node-highlight from #node-<id>`),
  keyed to the panel element's lifecycle rather than a server-rendered
  state.

## Loading states

- **`.loading::before`** — a braille-character spinner (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`),
  animated by cycling the `content` property through a `@keyframes`
  rule, defined once in `manage-project.css`. **Currently used in
  exactly one place**: the node-edit panel's per-field indicator-box
  (above), via the hyperscript-injected markup described there — not a
  graph-wide or app-wide loading affordance, despite being generic
  enough to promote to `global.css` if a second view ever needs the
  same spinner. Leave it scoped to `manage-project.css` until that
  actually happens; don't promote it speculatively.
- **`.flash`** (also `manage-project.css`) — a one-shot blue pulse
  (`@keyframes flashAnimation`) on a graph node's rect, triggered by
  `Node.Refresh.templateRefresh` when a background poll detects that
  node's title changed server-side: hyperscript adds `.flash`, waits
  500ms, removes it, then removes its own now-inert trigger element.
  This is the "flash-on-update" effect
  [`../../solution-proposals/e2e-testing.md`](../../solution-proposals/e2e-testing.md)
  §2 flags as a timing hazard for E2E tests — that doc's guidance
  (assert on the settled end state, never mid-transition) applies
  directly to this effect.

## `material.css`

Loads the Material Icons webfont (`.material-icons`) globally,
alongside `global.css`. Every `<i class="material-icons">...</i>` glyph
in the app (`mode_edit`, `check`, `close`, `done`, `error`) comes from
here. No real boundary question with `global.css` beyond that — it's a
single-purpose font-loading file, not a second design-token layer, so
there's nothing to reconcile between the two.
