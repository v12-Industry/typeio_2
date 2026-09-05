{-# LANGUAGE OverloadedStrings #-}

{- | Rendering an 'OrbitDiagram' as SVG.

The contents only — the navigable shell around them is 'graphFrame',
shared with every other visualization (#242), which is what gets this
drawing pan and zoom without a line of its own.

See @docs/architecture/orbital-dependency-weighted-graph.md@ (#229).
-}
module Domain.Project.Visualization.Orbital.View
  ( templateOrbit
  , discGroup
  , linkLine
  , nodeHue
  ) where

import Common.Web.Attributes
import Common.Web.Elements
import Control.Monad (forM_)
import Data.Int (Int64)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text, pack)
import qualified Data.Text as T
import Data.Text.Util (intToText)
import Domain.Project.Orbit.Types
  ( Bounds (..)
  , Disc (..)
  , Link (..)
  , NodeId (..)
  , OrbitConfig (..)
  , OrbitDiagram (..)
  , Point (..)
  , Size (..)
  , boundsSize
  )
import Domain.Project.Responder.Ui.ProjectManage.Link
  ( nodePanelLink
  , nodeRefreshLink
  )
import Domain.Project.Visualization.Common
  ( FrameBox (..)
  , graphFrame
  , pushUrl
  )
import Lucid

{- | The whole fragment: the shared viewport frame, with this drawing's
links and discs inside it.

__No root anchor is emitted, and that is the right answer rather than
an omission.__ This visualization has no root to open on, and
'graphFrame' already falls back to the centre of the drawing's natural
size — which for an orbital drawing /is/ the eye, exactly where a
reader should start. The behaviour comes free; reimplementing it would
be the mistake.
-}
templateOrbit :: Int64 -> OrbitConfig -> Map NodeId Text -> OrbitDiagram -> Html ()
templateOrbit pid cfg labels d =
  graphFrame box Nothing $ do
    g_ [id_ "graph-links"] $
      forM_ (odLinks d) linkLine
    g_ [id_ "graph-nodes"] $
      forM_ (odDiscs d) (discGroup pid cfg labels)
  where
    Bounds mn _ = odBounds d
    size = boundsSize (odBounds d)
    box =
      FrameBox
        { fbMinX = ptX mn
        , fbMinY = ptY mn
        , fbWidth = szW size
        , fbHeight = szH size
        }

{- | One dependency, drawn as a straight segment with the arrowhead on
the inner end — the dependent, the one waiting.

A plain two-point path rather than a polyline: nothing here bends.
'Domain.Project.Graph.Route'\'s ports, tracks and line jumps have no
counterpart in this drawing, and line jumps in particular would have
nothing to disambiguate — no two links cross.
-}
linkLine :: Link -> Html ()
linkLine (Link from to) =
  path_
    [ class_ "link"
    , d_ segment
    , fill_ "none"
    , markerEnd_ "url(#arrow)"
    ]
    (mempty :: Html ())
  where
    segment =
      T.concat
        [ "M"
        , dbl (ptX from)
        , ","
        , dbl (ptY from)
        , "L"
        , dbl (ptX to)
        , ","
        , dbl (ptY to)
        ]

{- | One drawn circle, with the node-panel wiring every visualization
owes the Project Manage UI.

Three things here are contracts rather than choices:

* __@data-node-id@__ (#234) is what lets the node panel's highlight and
  the post-edit flash find /every/ disc for this node, not just the
  first. It is the whole of what this visualization owes the
  surrounding UI.
* __The @hx-*@ attributes__ are the node-detail interaction, listed in
  @docs\/architecture\/graph-rendering.md@'s DOM contract. Clicking any
  replica opens the same node's panel and pushes the same URL, which is
  correct: they are the same node.
* __@#disc-\<id\>-\<replica\>@, not @#node-\<id\>@.__ A different
  prefix, deliberately. Several circles share a node here, so anything
  still querying @#node-\<id\>@ — a stylesheet, a test, a future hook —
  should find nothing rather than silently match one arbitrary replica.
  Silent partial matches are how a constant @node-label@ id survived
  from #173 to #178.

Only geometry is emitted as attributes. Fill, stroke, hover, the
highlight glow and the flash all live in @manage-project.css@, keyed off
the @work@ class the shape carries.
-}
discGroup :: Int64 -> OrbitConfig -> Map NodeId Text -> Disc -> Html ()
discGroup pid cfg labels disc =
  g_
    [ id_ ("disc-" <> discKey)
    , dataNodeId_ nid
    , class_ "disc"
    , -- Which node this is, as a number the stylesheet turns into a
      -- colour. A datum, not an appearance decision: saturation,
      -- lightness and the theme all stay in manage-project.css. See
      -- 'nodeHue'.
      style_ ("--node-hue: " <> nodeHue rawId)
    , {- Hovering any disc highlights every disc for the same node.

      Inline, on the element it governs -- not a script file and not a
      client-side node registry. CSS cannot express this: there is no
      selector for "every element sharing an attribute value with the
      hovered one", which is the whole reason it needs a behaviour.

      `.replica-hover` rather than `.node-highlight` deliberately. The
      node panel adds `.node-highlight` to these same elements on a
      different trigger, so sharing the class would make a mouseleave
      strip a highlight the open panel owns. The two classes share the
      glow in CSS and nothing else. -}
      h_ $
        "on mouseenter add .replica-hover to "
          <> nodeSel
          <> " on mouseleave remove .replica-hover from "
          <> nodeSel
    , hxGet_ (nodePanelLink rawId pid)
    , hxTrigger_ "click"
    , hxTarget_ "#node-panel"
    , hxPushUrl'_ (pushUrl rawId pid)
    , hxSwap_ "innerHTML"
    ]
    $ do
      circle_
        [ class_ "work"
        , cx_ (dbl (ptX centre))
        , cy_ (dbl (ptY centre))
        , r_ (dbl (cfgDiscRadius cfg))
        ]
        (mempty :: Html ())
      discLabel discKey centre (dLines disc)
      {- Re-fetch this disc's label when the node's detail panel closes
      after an edit (#244).

      One hook per replica, each aimed at its own label element. This is
      the one Project Manage hook that a selector change could not fix:
      hyperscript applies `to <selector/>` to every match, but an
      `hx-target` swaps exactly one element however many match. So a
      node drawn five times fires five requests and lands five swaps.

      Accepted rather than optimised. It is correct, needs no new
      endpoint, and the count is bounded by the ceiling on dependents
      (#231). The alternative -- one hook returning `hx-swap-oob`
      fragments -- was rejected because it would put "how many replicas
      does the current drawing have" inside an endpoint shared with the
      layered visualizations, which is layout knowledge leaking across
      the seam.

      The hook is a sibling of the label rather than inside it, so it
      survives the swap and the response does not have to carry a copy
      of itself. -}
      g_
        [ class_ "hidden"
        , hxGet_ (nodeRefreshLink rawId pid (cfgLabelWidth cfg) label)
        , hxTrigger_ $
            "nodePanel:onEditClosed[event.detail.nodeId=="
              <> nid
              <> "] from:#node-panel"
        , hxTarget_ ("#disc-text-" <> discKey)
        , hxSwap_ "innerHTML"
        , hxPushUrl_ False
        ]
        (mempty :: Html ())
  where
    NodeId rawId = dNode disc
    nid = intToText rawId
    discKey = nid <> "-" <> pack (show (dReplica disc))
    centre = dCentre disc
    nodeSel = "<[data-node-id='" <> nid <> "']/>"
    {- The untruncated title, which 'Disc' deliberately does not carry
    (it holds the label already wrapped to the circle). The refresh
    endpoint compares it against the stored one to decide whether
    anything changed, so it has to be the original. -}
    label = Map.findWithDefault T.empty (dNode disc) labels

{- | A disc's label, centred on the circle.

Positioned by a @transform@ on the @text@ rather than by @x@\/@y@ on it
and every @tspan@, for the same reason the layered drawing does it:
that puts the text origin at the centre, so a fragment swapped in later
lands correctly without knowing where the disc sits.

The id is @disc-text-\<id\>-\<replica\>@ — unique per circle, which is
what the per-node label refresh will need (#244). Nothing targets it
yet, and it is emitted now so that issue is a hook change rather than a
markup change.
-}
discLabel :: Text -> Point -> [Text] -> Html ()
discLabel discKey (Point cx cy) ls =
  text_
    [ id_ ("disc-text-" <> discKey)
    , transform_ ("translate(" <> dbl cx <> "," <> dbl cy <> ")")
    , dy_ "0.35em"
    ]
    $ forM_ (zip [0 :: Int ..] ls)
    $ \(i, l) ->
      tspan_
        [ x_ "0"
        , dy_ (if i == 0 then firstDy else "1.1em")
        ]
        (toHtml l)
  where
    blockLift = 1.1 * fromIntegral (length ls - 1) / 2 :: Double
    firstDy
      | blockLift == 0 = "0em"
      | otherwise = (<> "em") . pack . show . negate $ blockLift

{- | A node's hue, in degrees: a __golden-angle rotation__ over its id.

Colour is what tells a reader that three circles are one node, so it has
to be stable across a node's replicas and across renders, and adjacent
nodes have to be tellable apart. Rotating by the golden angle
(137.508°) gives both — consecutive ids land on opposite sides of the
wheel — and needs no palette table.

__Keyed on the node's id rather than its position in a sorted list__,
which is a deliberate departure from what
@docs\/architecture\/orbital-dependency-weighted-graph.md@ specifies.
Position-based hues are only stable while the node set is: add or delete
one node and every node after it changes colour, which is exactly the
cue a reader has learned to rely on. An id never changes, and because
ids come from a serial column they are near-consecutive, so the spread
is the same one the golden angle was chosen for.

Computed in integers rather than by multiplying a 'Double': at large ids
the fractional part of the product is where all the information is, and
that is the part floating point loses first.

Hashing the id instead was considered and rejected — it gives no spread
guarantee, so a small project can easily draw two neighbouring nodes in
near-identical colours, which in /this/ drawing is not a cosmetic
problem but a false statement that they are the same node.
-}
nodeHue :: Int64 -> Text
nodeHue nodeId = dbl (fromIntegral thousandths / 1000)
  where
    -- 137.508 degrees, in thousandths, kept exact.
    thousandths = (nodeId * 137508) `mod` 360000

{- | Coordinates render as plain integers where they are whole, rather
than as @80.0@ — matching the layered drawing's own @dblText@.
-}
dbl :: Double -> Text
dbl x
  | x == fromIntegral (round x :: Int) = pack (show (round x :: Int))
  | otherwise = pack (show x)
