# Hyperscript

[hyperscript](https://hyperscript.org) (loaded from a CDN, pinned to
`0.9.14`, in `IndexView.hs`) provides the `_` HTML attribute — wrapped as
`h_` in `Common.Web.Attributes` — for small, imperative, per-element
behaviors that don't warrant reaching for a real script file or a new
htmx round trip. Everything below is the entire current inventory of
hyperscript usage in the app; there isn't a larger convention hiding
elsewhere.

## Fade in on load

```haskell
svg_ [ ..., h_ "on load transition my opacity to 1 over 200ms" ] $ do ...
```

(`ProjectManage/Graph.hs`) The simplest form: one event (`on load`), one
imperative action, no state.

## The "throwaway trigger element" idiom

```haskell
g_ [ class_ "hidden"
   , h_ $ "on load add .flash to " <> nsel
          <> " then wait 500ms"
          <> " then remove .flash from " <> nsel
          <> " then remove me"
   ] empty
```

(`ProjectManage/Node/Refresh.hs`, `templateRefresh`) This element renders
nothing (`class_ "hidden"`, empty body) — its only job is to run a
sequenced script once when it's swapped into the DOM (flash the node,
wait, un-flash it) and then delete itself (`remove me`). This is the
pattern for "run this one-off effect as a side effect of an htmx swap
landing," when there's no other element around that's a natural place to
attach the behavior to. If you need a similar one-shot effect elsewhere,
this is the idiom to reach for rather than inventing a new one.

## Reacting to input

```haskell
textarea_ [ ...
          , h_ "on input transition <label[for=\"description\"] .indicator-box i /> opacity to 0"
          ] (toHtml . M.nodeDescription $ nde)
```

(`ProjectManage/Node/Edit.hs`) hyperscript's `<selector/>` syntax reaches
outside the element itself — here, fading out a sibling status icon the
moment the user starts typing again, ahead of the htmx autosave request
that fires 500ms later (see [htmx.md](htmx.md)'s inline-edit-autosave
pattern — the two are meant to run together on the same field).

## Local per-element state

```haskell
input_ [ ...
       , h_ $ "init set my.icount to 0 "
             <> "on input increment my.icount "
             <> "if my.icount mod 8 === 0 "
             <> "then set #title-indicator's innerHTML to '"
             <> (toStrict . renderText $ ld)
             <> "'"
       ]
```

(`ProjectManage/Node/Edit.hs`, the title field) `my.icount` is state
scoped to this one element, initialized once (`init`), incremented on
every keystroke, used to re-trigger a loading-spinner indicator
periodically while the user is still typing (every 8th keystroke) rather
than only once. This is the most involved hyperscript in the app — it's
doing small stateful logic that would otherwise need a few lines of real
JS, kept as a one-liner because the state and its lifetime are entirely
local to this one input.

## When to reach for hyperscript vs. CSS vs. real JS

Going by what's actually here:

- **Plain CSS transition/animation**: prefer this first if the effect is
  purely presentational and doesn't need to be triggered by a specific
  DOM event or sequenced with other steps (a `:hover` state, for
  example, needs neither hyperscript nor htmx).
- **Hyperscript (`h_`)**: for effects tied to one element's own
  lifecycle/events (`on load`, `on input`, ...) that need light
  imperative logic — sequencing (`then`), simple per-element state
  (`init`/`my.x`), or reaching a nearby element via a selector. Every
  example above is one to a handful of clauses; if it's growing past
  that, it's a signal to stop.
- **Real JS (`graph-viewport.js`)**: for anything with actual
  application logic, data structures, or cross-element coordination at
  scale — the graph viewport's zoom/pan bookkeeping is never going to be
  a hyperscript one-liner, and isn't. Note that the graph's *layout* is
  not on this list at all any more: it is computed server-side in
  Haskell, which is the far better answer where it's
  available.
