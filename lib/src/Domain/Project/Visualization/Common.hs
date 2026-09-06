{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Visualization.Common where

import Common.Validation
  ( ValidationErr
  , isNotEmpty
  , isThere
  , orDefault
  , runValidation
  , valRead
  , (.$)
  )
import Common.Web.Attributes
import Common.Web.Elements
import Common.Web.Query (lookupVal)
import Config.Visualization (Visualization, defaultVisualization)
import Control.Monad (forM_)
import Control.Monad.Reader (ReaderT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either (hoistEither, runEitherT)
import Data.Aeson (encode, object, (.=))
import Data.Bifunctor (first)
import Data.Either (notNullEither)
import Data.Int (Int64)
import Data.List (sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text, pack, unpack)
import qualified Data.Text as T
import Data.Text.Util (intToText, wrapLabel)
import Database.Esqueleto.Experimental
  ( from
  , fromSqlKey
  , in_
  , select
  , table
  , toSqlKey
  , val
  , valList
  , where_
  , (==.)
  )
import Database.Persist (Entity (..))
import Database.Persist.Sql (ConnectionPool, SqlBackend, runSqlPool)

import Domain.Project.Graph.Layout (layout)
import Domain.Project.Graph.Types
  ( Bounds (..)
  , Diagram (..)
  , EdgeId (..)
  , EdgeKind (..)
  , LayoutConfig (..)
  , LayoutEdge (..)
  , LayoutNode (..)
  , NodeId (..)
  , NodeKind (..)
  , PlacedEdge (..)
  , PlacedNode (..)
  , Point (..)
  , Size (..)
  , boundsSize
  , defaultLayoutConfig
  , dependsOn
  )
import qualified Domain.Project.Model as M
  ( Dependency (..)
  , Node (..)
  , Project (..)
  , unNodeTypeKey
  )
import Domain.Project.Responder.Ui.ProjectManage.Link
import Lucid
import Network.HTTP.Types (queryToQueryText, status200, status403)
import Network.HTTP.Types.URI (QueryText)
import Network.Wai
  ( Application
  , Request (queryString)
  , Response
  , ResponseReceived
  , responseLBS
  )

data GetGraphError
  = InvalidParams [ValidationErr]
  | MissingNodes

{- | A node, as much of it as the graph's own rendering needs.

What used to be here alongside this was a @Graph@ record with @ToJSON@
instances, serialised into a @#graph-data@ script tag for the browser
to lay out. The server computes the layout now (#181), so the graph
never leaves the server as data — it leaves as finished SVG.
-}
data GraphNode = GraphNode
  { graphNodeId :: Int64
  , label :: Text
  , nodeType :: Text
  , projectId :: Int64
  }

{- | Build a 'ServerGraph' from a project's rows: which nodes and edges
the drawing is /of/.

This is what the /layered/ visualizations differ by — whether the
project root is drawn at all, whether containment edges are derived,
what counts as an edge.

It is deliberately __not__ the seam between visualizations in general.
A 'ServerGraph' carries a 'Diagram', and 'serverGraph' produces one by
calling the layered layout engine, so every drawing expressible through
this type is a layered one by construction. 'RenderGraph' is the seam;
this is one convenient way to reach it. See
@docs/architecture/visualization-switching.md@.
-}
type BuildGraph =
  Int64 ->
  [Entity M.Node] ->
  [Entity M.Dependency] ->
  ServerGraph

{- | Render a project's rows as the finished fragment. This is the one
thing each visualization supplies for itself.

The seam sits at /render the drawing/ rather than at /decide the nodes
and edges/ ('BuildGraph') because the latter cannot express a
visualization that is not layered: 'Diagram' is layered geometry, and
'templateServerGraph' renders rects and orthogonal paths. A radial or
force-directed visualization brings its own geometry and its own
document assembly and imports neither.

A layered visualization is then a composition of pieces it already had:

@
renderGraph pid ns ds = 'templateServerGraph' (buildGraph pid ns ds)
@
-}
type RenderGraph =
  Int64 ->
  [Entity M.Node] ->
  [Entity M.Dependency] ->
  Html ()

{- | The request half of a graph endpoint, shared by every
visualization: parse the project id, fetch the project's nodes and
dependencies, hand them to the visualization's own 'RenderGraph'.

Only that step varies, so only that step is a parameter. Validation, the
queries and the error responses are identical whichever drawing is
selected, and duplicating them per visualization would just let them
drift apart.
-}

{- | The graph endpoint: pick the visualization the request asked for,
then render with it.

This is the switch (#223). It sits here rather than in the container
because everything it needs — the query text, the validation vocabulary,
and the error-response shape — is already here, and because the
alternative is a second copy of @respondValErrs@ somewhere else.

The parameter is a /function/ from 'Visualization' to 'RenderGraph',
not a 'Visualization': this module never learns which drawings exist,
it just applies the table the container hands it. That keeps the
per-visualization list in one place and keeps this function honest
about being shared — it is the mechanism, not a branch on identity.
See @docs/architecture/visualization-switching.md@.
-}
handleGraph ::
  (Visualization -> RenderGraph) ->
  ConnectionPool ->
  Application
handleGraph renderFor pl req respond =
  case validateVisualization qt of
    Left es -> respondValErrs respond es
    Right viz -> handleGraphWith (renderFor viz) pl req respond
  where
    qt = queryToQueryText . queryString $ req

{- | A validation failure, in the shape every graph-endpoint error uses.

Top-level rather than a @where@ binding because two callers need it now:
the project id's validation inside 'handleGraphWith', and the
visualization's before it (#223). One shape, one place.
-}
respondValErrs ::
  (Response -> IO ResponseReceived) ->
  [ValidationErr] ->
  IO ResponseReceived
respondValErrs respond es =
  respond
    . responseLBS
      status403
      [("Content-Type", "application/json")]
    . encode
    . object
    $ ["error" .= (mconcat . map (pack . show) $ es)]

{- | The visualization a request asks for, or 'defaultVisualization'.

Optional, so this uses 'valRead' without 'isThere': an absent parameter
passes straight through with no error and takes the default, while a
/present but unrecognised/ one is a validation error rather than a
silent fallback.

That asymmetry is the point. Until #223 the selection came from
@GRAPH_VISUALIZATION@ and a missing value failed at boot, on the
reasoning that a silently defaulted visualization surfaces much later
as "the graph looks wrong". That reasoning applies to a value somebody
got /wrong/, and this keeps it — @?visualizationMode=Radial@ is an
error. It never applied to a value nobody supplied, which is just an
ordinary link.

One ordinary 'runValidation' pipeline, like every other validator here.
'orDefault' is what makes that possible: it supplies the value for a
field that was legitimately absent without suppressing an error for one
that was present and wrong, so both cases stay expressible in the same
chain. Its own docs explain why it has to come last.
-}
validateVisualization :: QueryText -> Either [ValidationErr] Visualization
validateVisualization qt =
  runValidation id $
    lookupVal "visualizationMode" qt
      .$ unpack
      >>= valRead "Invalid visualizationMode value"
      >>= orDefault defaultVisualization

handleGraphWith :: RenderGraph -> ConnectionPool -> Application
handleGraphWith drawGraph pl req respond = do
  rslt <- flip runSqlPool pl . runEitherT $ do
    pid <-
      hoistEither
        . first InvalidParams
        . validateProjectId
        $ qt
    ns <-
      lift (queryNodes pid)
        >>= hoistEither
          . notNullEither MissingNodes
    ds <-
      lift
        . queryDependencies
        . fmap (fromSqlKey . entityKey)
        $ ns
    pure (pid, ns, ds)
  case rslt of
    Left (InvalidParams es) -> respondValErrs respond es
    Left MissingNodes -> respondMissingNodes
    Right (pid, ns, ds) ->
      respondSuccess $ drawGraph pid ns ds
  where
    respondMissingNodes =
      respond
        . responseLBS
          status403
          [("Content-Type", "application/json")]
        . encode
        . object
        $ ["error" .= ("No nodes found for the project" :: Text)]
    respondSuccess =
      respond
        . responseLBS
          status200
          [("Content-Type", "text/html")]
        . renderBS
    qt =
      queryToQueryText
        . queryString
        $ req

pushUrl :: Int64 -> Int64 -> Text
pushUrl nid pid =
  "/ui/project/vw"
    <> "?projectId="
    <> (pack . show $ pid)
    <> "&nodeId="
    <> (pack . show $ nid)

queryNodes :: Int64 -> ReaderT SqlBackend IO [Entity M.Node]
queryNodes pid = do
  select $ do
    n <- from $ table @M.Node
    where_ (n.projectId ==. val pkey)
    pure n
  where
    pkey = toSqlKey @M.Project pid

queryDependencies :: [Int64] -> ReaderT SqlBackend IO [Entity M.Dependency]
queryDependencies [] = return []
queryDependencies nids = do
  select $ do
    d <- from $ table @M.Dependency
    where_ (d.nodeId `in_` valList nkeys)
    pure d
  where
    nkeys = toSqlKey @M.Node <$> nids

toGraphNode :: Entity M.Node -> GraphNode
toGraphNode (Entity k e) =
  GraphNode
    { graphNodeId = fromSqlKey k
    , projectId = fromSqlKey . M.nodeProjectId $ e
    , label = pack . M.nodeTitle $ e
    , nodeType = pack . M.unNodeTypeKey . M.nodeNodeTypeId $ e
    }

{- | A node's label, re-wrapped and laid out, for 'Node.Refresh' to swap
in after an edit.

@wrapWidth@ is the asking shape's own, taken from the request — see
'Domain.Project.Responder.Ui.ProjectManage.Link.nodeRefreshLink'. A
circle fits fewer characters per line than the box the layered node
became in #178, and this endpoint serves both.

__This emits the label and nothing else.__ It used to carry a copy of
the refresh hook as well, which was redundant: the drawing emits that
hook as a /sibling/ of the label element, so it survives a swap that
replaces only the label's contents. Carrying a second copy inside the
swapped content meant two hooks fired on every edit after the first —
harmless, but two requests for one change — and it hardcoded
@#node-text-\<id\>@ as the target, which is the layered drawing's id
scheme and not every drawing's (#244).

Keeping the hook with the drawing rather than in the response is also
the right division: which element to swap into is a fact about the
drawing, and the drawing is what knows it.
-}
nodeContents :: Int -> GraphNode -> Html ()
nodeContents wrapWidth = labelTspans wrapWidth . label

-- | Wrap a raw title to the asking shape, then lay the lines out.
labelTspans :: Int -> Text -> Html ()
labelTspans wrapWidth =
  tspanLines
    . wrapLabel
      wrapWidth
      (cfgLabelLines defaultLayoutConfig)

-- SVG `<text>` has no wrapping of its own, so a multi-line label has to
-- be emitted as one `<tspan>` per line. Each line resets `x` to the
-- node's own origin (otherwise tspans just continue along the same
-- line) and steps `dy` by one line height, with the first line lifted
-- by half the block's height so the whole label stays vertically
-- centred on the node however many lines it wraps to.
--
-- `x="0"` means "the text origin", which 'nodeLabel' arranges to be the
-- centre of the node box by translating the `<text>` there. That is
-- what lets Node.Refresh return one of these fragments and have it land
-- correctly without knowing anything about where the node sits.
tspanLines :: [Text] -> Html ()
tspanLines ls =
  forM_ (zip [0 :: Int ..] ls) $ \(i, l) ->
    tspan_
      [ x_ "0"
      , dy_ $ if i == 0 then firstDy else lineHeight
      ]
      $ toHtml l
  where
    lineHeight = "1.1em"
    -- Half the block's height, which the first line is lifted by. Zero
    -- is spelt out rather than negated: a one-line label would
    -- otherwise render as `dy="-0.0em"`, which is the same offset but
    -- reads like a bug in the markup.
    blockLift = 1.1 * fromIntegral (length ls - 1) / 2 :: Double
    firstDy
      | blockLift == 0 = "0em"
      | otherwise = (<> "em") . pack . show . negate $ blockLift

validateProjectId :: QueryText -> Either [ValidationErr] Int64
validateProjectId qt = runValidation id $ do
  lookupVal "projectId" qt
    .$ unpack
    >>= isThere "Project id must be present"
    >>= isNotEmpty "Project id must have a value"
    >>= valRead "Project id must be valid integer"

-- ---------------------------------------------------------------------
-- Server-computed layout (#173-#181)
--
-- Everything below renders a Diagram that Domain.Project.Graph.Layout
-- has already placed. It was opt-in behind ?layout=server while it was
-- being built; #181 made it the only renderer and removed both the flag
-- and the client-rendered template it used to sit beside.
-- See docs/architecture/graph-rendering.md.
-- ---------------------------------------------------------------------

data ServerGraph = ServerGraph
  { sgProjectId :: Int64
  , sgLabels :: Map NodeId Text
  {- ^ Untruncated titles, which 'PlacedNode' deliberately doesn't
  carry (it holds the label already wrapped to the box). The
  per-node refresh hook needs the original.
  -}
  , sgDiagram :: Diagram
  }

{- | Assemble a 'ServerGraph' from nodes and edges a visualization has
already decided on, laying them out with the shared engine.

The labels map carries the untruncated titles, which 'PlacedNode'
deliberately doesn't (it holds the label already wrapped to the box) —
the per-node refresh hook needs the original.
-}
serverGraph :: Int64 -> [LayoutNode] -> [LayoutEdge] -> ServerGraph
serverGraph pid lns les =
  ServerGraph
    { sgProjectId = pid
    , sgLabels = Map.fromList [(lnId n, lnLabel n) | n <- lns]
    , sgDiagram = layout defaultLayoutConfig lns les
    }

toLayoutNode :: Entity M.Node -> LayoutNode
toLayoutNode (Entity k e) =
  LayoutNode
    { lnId = NodeId (fromSqlKey k)
    , lnKind =
        if M.unNodeTypeKey (M.nodeNodeTypeId e) == "project_root"
          then RootNode
          else WorkNode
    , lnLabel = pack (M.nodeTitle e)
    }

{- | @project.dependency@ stores @node_id@ /depends on/ @to_node_id@
(see @docs/development/backend/database-schema.md@), so @node_id@ is the
dependent — the end that carries the arrowhead — and @to_node_id@ is the
dependency.

This is the opposite of what the old client-side conversion built,
whose @source@/@target@ naming let the arrowhead end up on the
dependency.
-}
toLayoutEdge :: Entity M.Dependency -> LayoutEdge
toLayoutEdge (Entity k e) =
  dependsOn
    (EdgeId (fromSqlKey k))
    (NodeId (fromSqlKey (M.dependencyToNodeId e)))
    (NodeId (fromSqlKey (M.dependencyNodeId e)))

{- | The navigable shell every visualization's drawing sits inside:
the @\<svg\>@, the zoom layer, and the viewport script.

Takes the drawing's bounds, optionally a point to open centred on __in
the drawing's own coordinates__, and the drawing itself.

Six things in here are load-bearing and none of them are apparent from
reading the markup, which is the reason this is one shared function
rather than something each visualization assembles for itself. A
visualization that hand-rolled it would get pan and zoom subtly wrong,
and nothing — not the type checker, not a unit test — would say so.

* __The @\<svg\>@ deliberately has no @viewBox@.__ It is
  @width=\"100%\" height=\"100%\"@, so one user unit is one CSS pixel
  and the drawing sits at natural size until the transform says
  otherwise. A @viewBox@ would scale it to fit its container, which is
  exactly the fit-to-screen behaviour the viewport exists to avoid: a
  large project is meant to overflow and be navigated, not shrunk until
  its titles stop being readable.
* __@data-base-width@ \/ @data-base-height@__ carry the natural size,
  which the client centres on when there is no anchor.
* __@#graph-zoom-layer@ is the one element @d3-zoom@ writes to.__
  Everything the viewport does — pan, zoom, recentre — is a @transform@
  on this group and nothing else.
* __The origin shift__ moves the drawing's top-left to the origin, which
  is what makes the zoom layer's coordinate system the same one the
  anchor is emitted in. Without it the client would have to know the
  bounds to place the anchor.
* __The anchor is converted here__, from the caller's coordinates to
  that top-left-relative system. Callers pass a point from their own
  geometry and this does the arithmetic, so the conversion cannot be got
  wrong twice in two visualizations.
* __The script tag is inside the fragment__, not loaded once at page
  load. htmx swaps this whole subtree into @#tree-container@ on every
  graph load, so anything bound to the drawing has to arrive with it —
  and it is also what keeps d3 off every other page in the app.

'arrowMarker' is emitted here as @#arrow@ because every drawing so far
wants one. A visualization needing a different arrowhead adds its own
@\<defs\>@ inside @contents@ under a different id rather than this
growing a parameter — SVG permits several @defs@ blocks, and a flag here
would be the exact failure mode
@docs\/architecture\/visualization-switching.md@ warns about.
-}

{- | What 'graphFrame' needs to know about a drawing, in the drawing's
own coordinates.

__Deliberately not 'Domain.Project.Graph.Types.Bounds'.__ The frame is
the viewport, and the viewport has no opinion about geometry — but
typing it in the /layered/ engine's records would mean a visualization
that brings its own geometry has to import that engine anyway, purely
to describe a rectangle. That would make
@docs\/architecture\/visualization-switching.md@'s "a visualization that
is not layered simply does not import @Domain.Project.Graph.*@" false in
the one case it exists for. Four doubles cost nothing and keep it true.
-}
data FrameBox = FrameBox
  { fbMinX :: Double
  , fbMinY :: Double
  -- ^ The drawing's top-left, whatever coordinates it was laid out in.
  , fbWidth :: Double
  , fbHeight :: Double
  }

graphFrame :: FrameBox -> Maybe (Double, Double) -> Html () -> Html ()
graphFrame box anchor contents =
  do
    svg_
      ( [ id_ "tree-view"
        , width_ "100%"
        , height_ "100%"
        , dataBaseWidth_ (dblText (fbWidth box))
        , dataBaseHeight_ (dblText (fbHeight box))
        , h_ "on load transition my opacity to 1 over 200ms"
        ]
          <> anchorAttrs
      )
      $ do
        defs_ [] arrowMarker
        g_ [id_ "graph-zoom-layer"] $
          g_ [transform_ originShift] contents
    script_ [src_ "/static/script/graph-viewport.js"] (mempty :: Html ())
  where
    originShift =
      T.concat
        [ "translate("
        , dblText (negate (fbMinX box))
        , ","
        , dblText (negate (fbMinY box))
        , ")"
        ]
    anchorAttrs = case anchor of
      Nothing -> []
      Just (ax, ay) ->
        [ dataRootX_ (dblText (ax - fbMinX box))
        , dataRootY_ (dblText (ay - fbMinY box))
        ]

-- | A 'FrameBox' from the layered engine's own bounds.
layeredFrameBox :: Bounds -> FrameBox
layeredFrameBox bnds =
  FrameBox
    { fbMinX = ptX mn
    , fbMinY = ptY mn
    , fbWidth = szW size
    , fbHeight = szH size
    }
  where
    Bounds mn _ = bnds
    size = boundsSize bnds

{- | The layered drawing, inside the shared 'graphFrame'.

The frame is the navigable shell; this supplies only what goes in it,
which for a layered drawing is two groups — the edges and the nodes.
They stay here rather than in the frame because they are this drawing's
structure, not the viewport's: a visualization is not obliged to have
exactly two layers.

The anchor is the project root, which the server has already placed, so
the client never has to hunt the DOM for it. A drawing with no root
('layout' is total, so this is possible) passes 'Nothing' and the client
falls back to the middle of the drawing.
-}
templateServerGraph :: ServerGraph -> Html ()
templateServerGraph sg =
  graphFrame (layeredFrameBox (diagramBounds d)) anchor $ do
    g_ [id_ "graph-links"] $
      forM_ (diagramEdges d) edgeLine
    g_ [id_ "graph-nodes"] $
      forM_ (diagramNodes d) (nodeGroup sg)
  where
    d = sgDiagram sg
    anchor = (\(Point ax ay) -> (ax, ay)) <$> diagramRootAnchor d

{- Note: the on-screen zoom/recentre button cluster that used to live
here is gone. It existed because #179's viewport panned by scrolling a
container whose scrollbars are hidden, which left a user who had panned
into empty space with no way back and no visible zoom affordance.

The d3-zoom viewport that replaced it recentres on double-click (and on
@0@ from the keyboard, with the arrow keys and @+@/@-@ covering the rest
of what the buttons did), so the way back no longer needs three
permanent buttons sitting on top of the drawing. See
@static/script/graph-viewport.js@ for the full gesture list.
-}

arrowMarker :: Html ()
arrowMarker =
  marker_
    [ id_ "arrow"
    , viewBox_ "0 -5 10 10"
    , refX_ "10"
    , refY_ "0"
    , markerWidth_ "6"
    , markerHeight_ "6"
    , orient_ "auto"
    ]
    $ path_ [d_ "M0,-5L10,0L0,5", fill_ "#999"] (mempty :: Html ())

{- | The polyline's last point is the dependent end, so @marker-end@
puts the arrowhead on the node that is waiting — not on the one that
has to finish first.
-}

{- | Every edge gets an arrowhead, including the root's (#206).

A project's completion depends on its work being complete, so the root
genuinely is waiting on every node under it — the same thing the arrow
means anywhere else in this drawing. The polyline already ends at the
root, so the head lands there: this work feeds the project.

#198 briefly removed it, on the reasoning that membership isn't a
dependency and nothing is waiting on anything. The first half is right
and still stands — membership is derived from @project_id@, not stored
as a duplicate row — but the second half isn't, which is why the arrow
is back.

'Contains' still earns its own class: these edges are /derived/ rather
than read from @project.dependency@, and nothing behind them can be
deleted. The class is the hook for that, not a visual difference.
-}
edgeLine :: PlacedEdge -> Html ()
edgeLine e =
  path_
    [ class_ (if derived then "link link-contains" else "link")
    , d_ (polyline (peJumps e) (pePoints e))
    , fill_ "none"
    , markerEnd_ "url(#arrow)"
    ]
    (mempty :: Html ())
  where
    derived = peKind e == Contains

{- | The edge's path, hopping over each of its 'peJumps' (#180).

Which crossings get a hop is decided by the layout engine; this only
draws them. A hop is a semicircular arc of 'cfgJumpRadius' replacing
the middle of the run, always bulging towards the top of the page so a
row of them reads as one convention rather than a wobble.
-}
polyline :: [Point] -> [Point] -> Text
polyline _ [] = ""
polyline jumps (p : ps) =
  "M" <> point p <> mconcat (zipWith run (p : ps) ps)
  where
    point (Point x y) = dblText x <> "," <> dblText y

    run (Point x0 y0) q@(Point x1 y1)
      -- Vertical runs are drawn straight through: only the horizontal
      -- side of a crossing hops (see 'addJumps').
      | y0 /= y1 || null hops = " L" <> point q
      | otherwise = mconcat (map hop hops) <> " L" <> point q
      where
        rightward = x1 > x0
        -- In travel order, so the arcs come out along the run rather
        -- than doubling back to an earlier one.
        hops =
          (if rightward then id else reverse)
            . sort
            $ [ jx
              | Point jx jy <- jumps
              , jy == y0
              , jx > min x0 x1
              , jx < max x0 x1
              ]

        hop jx =
          " L"
            <> point (Point (jx - dir * r) y0)
            <> " A"
            <> dblText r
            <> ","
            <> dblText r
            <> " 0 0 "
            -- The sweep flag has to flip with direction of travel to
            -- keep every hop bulging the same way. 1 is the
            -- positive-angle direction, which reads as clockwise in
            -- SVG's y-down space: clockwise from the left end goes over
            -- the top, and so does counter-clockwise from the right
            -- end. Both arcs below therefore bulge upward.
            <> (if rightward then "1 " else "0 ")
            <> point (Point (jx + dir * r) y0)
          where
            dir = if rightward then 1 else -1

    r = cfgJumpRadius defaultLayoutConfig

nodeGroup :: ServerGraph -> PlacedNode -> Html ()
nodeGroup sg n =
  g_
    [ id_ ("node-" <> nid)
    , -- Which node this element stands for (#234). The id above says
      -- the same thing, but an id can only ever name one element, and
      -- the Project Manage hooks have to work on a drawing that
      -- renders a node more than once. Additive: `#node-<id>` stays,
      -- since graph-rendering.md lists it as a contract and
      -- graph.spec.ts locates nodes by it.
      dataNodeId_ nid
    , class_ "node"
    , transform_ ("translate(" <> dblText (ptX tl) <> "," <> dblText (ptY tl) <> ")")
    , hxGet_ (nodePanelLink rawId pid)
    , hxTrigger_ "click"
    , hxTarget_ "#node-panel"
    , hxPushUrl'_ (pushUrl rawId pid)
    , hxSwap_ "innerHTML"
    ]
    $ do
      -- Only geometry is set here. Fill, stroke, hover, the
      -- `.node-highlight` glow and the `.flash` animation all live in
      -- manage-project.css, keyed off the `root`/`work` class -- the
      -- keyed off the class rather than the element name, which is
      -- what made removing the old circle (#182) cost nothing here.
      rect_
        [ class_ (kindClass (pnKind n))
        , width_ (dblText (szW sz))
        , height_ (dblText (szH sz))
        , rx_ "6"
        ]
        (mempty :: Html ())
      nodeLabel nid sz (pnLines n)
      -- Re-fetch this node's label when its detail panel closes after
      -- an edit.
      g_
        [ class_ "hidden"
        , hxGet_
            ( nodeRefreshLink
                rawId
                pid
                (cfgLabelWidth defaultLayoutConfig)
                rawLabel
            )
        , hxTrigger_ $
            "nodePanel:onEditClosed[event.detail.nodeId=="
              <> nid
              <> "] from:#node-panel"
        , hxTarget_ ("#node-text-" <> nid)
        , hxSwap_ "innerHTML"
        , hxPushUrl_ False
        ]
        (mempty :: Html ())
  where
    NodeId rawId = pnId n
    nid = intToText rawId
    pid = sgProjectId sg
    tl = pnTopLeft n
    sz = pnSize n
    rawLabel = Map.findWithDefault "" (pnId n) (sgLabels sg)

kindClass :: NodeKind -> Text
kindClass RootNode = "root"
kindClass WorkNode = "work"

{- | SVG has no text wrapping, so each label line is its own @tspan@.
Lines arrive pre-wrapped from the layout engine ('pnLines'); this only
positions them, centred in the box however many there are.

Two details here are load-bearing rather than stylistic:

* The id is @node-text-<id>@. It is what the
  per-node refresh hook swaps into after an edit, and it has to be
  unique per node -- this element used to carry a constant
  @node-label@, which both repeated one id across every node in the
  document and left the refresh hook aimed at a target that was never
  there.
* The centring is a @transform@ on the @text@ element rather than
  @x@\/@y@ on it and on every @tspan@. That puts the text origin at the
  middle of the box, so the @tspan@s inside sit relative to a centre
  (see 'tspanLines') -- which is what lets the refresh endpoint return
  one fragment that lands correctly wherever the node sits.
-}
nodeLabel :: Text -> Size -> [Text] -> Html ()
nodeLabel nid (Size w h) ls =
  text_
    [ id_ ("node-text-" <> nid)
    , transform_
        ( "translate("
            <> dblText (w / 2)
            <> ","
            <> dblText (h / 2)
            <> ")"
        )
    , -- Centres a single line on the baseline; 'tspanLines' lifts the
      -- block up from there as it grows past one line.
      dy_ "0.35em"
    ]
    $ tspanLines ls

{- | Coordinates render as plain integers where they are whole, which
most are, rather than as @80.0@.
-}
dblText :: Double -> Text
dblText v
  | v == fromIntegral rounded = intToText rounded
  | otherwise = pack (show v)
  where
    rounded = round v :: Int
