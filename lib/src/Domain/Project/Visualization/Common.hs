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
  , runValidation
  , valRead
  , (.$)
  )
import Common.Web.Attributes
import Common.Web.Elements
import Common.Web.Query (lookupVal, setQueryParam)
import Config.Visualization
  ( Visualization
  , VisualizationChoice (..)
  , resolveVisualization
  )
import Control.Monad (forM_)
import Control.Monad.Reader (ReaderT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either (hoistEither, runEitherT)
import Data.Aeson (encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.Either (notNullEither)
import Data.Int (Int64)
import Data.List (sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text, pack, unpack)
import qualified Data.Text as T
import Data.Text.Util (intToText, slug, wrapLabel)
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
  , unNodeStatusKey
  , unNodeTypeKey
  )
import Domain.Project.Responder.Ui.ProjectManage.Link
import Lucid
import Network.HTTP.Types (queryToQueryText, status200, status302, status403)
import Network.HTTP.Types.URI (QueryText, queryTextToQuery, renderQuery)
import Network.Wai
  ( Application
  , Request (queryString, rawPathInfo)
  , Response
  , ResponseReceived
  , responseLBS
  )

data GetGraphError
  = InvalidParams [ValidationErr]
  | MissingNodes

data GraphNode = GraphNode
  { graphNodeId :: Int64
  , label :: Text
  , nodeType :: Text
  , projectId :: Int64
  }

type BuildGraph =
  Int64 ->
  [Entity M.Node] ->
  [Entity M.Dependency] ->
  ServerGraph

type RenderGraph =
  Int64 ->
  [Entity M.Node] ->
  [Entity M.Dependency] ->
  Html ()

handleGraph ::
  (Visualization -> RenderGraph) ->
  ConnectionPool ->
  Application
handleGraph renderFor pl req respond =
  case resolveVisualization (lookupVal "visualizationMode" qt) of
    FellBack viz -> respondVisualizationFallback respond req qt viz
    AsRequested viz -> handleGraphWith (renderFor viz) pl req respond
  where
    qt = queryToQueryText . queryString $ req

respondVisualizationFallback ::
  (Response -> IO ResponseReceived) ->
  Request ->
  QueryText ->
  Visualization ->
  IO ResponseReceived
respondVisualizationFallback respond req qt viz =
  respond $
    responseLBS
      status302
      [("Location", visualizationLocation req qt viz)]
      mempty

visualizationLocation :: Request -> QueryText -> Visualization -> ByteString
visualizationLocation req qt viz =
  rawPathInfo req
    <> renderQuery True (queryTextToQuery corrected)
  where
    corrected = setQueryParam "visualizationMode" (pack (show viz)) qt

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

nodeContents :: Int -> GraphNode -> Html ()
nodeContents wrapWidth = labelTspans wrapWidth . label

labelTspans :: Int -> Text -> Html ()
labelTspans wrapWidth =
  tspanLines
    . wrapLabel
      wrapWidth
      (cfgLabelLines defaultLayoutConfig)

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

data ServerGraph = ServerGraph
  { sgProjectId :: Int64
  , sgLabels :: Map NodeId Text
  , sgStatuses :: Map NodeId Text
  , sgDiagram :: Diagram
  }

serverGraph ::
  Int64 ->
  Map NodeId Text ->
  [LayoutNode] ->
  [LayoutEdge] ->
  ServerGraph
serverGraph pid statuses lns les =
  ServerGraph
    { sgProjectId = pid
    , sgLabels = Map.fromList [(lnId n, lnLabel n) | n <- lns]
    , sgStatuses = statuses
    , sgDiagram = layout defaultLayoutConfig lns les
    }

nodeStatuses :: [Entity M.Node] -> Map NodeId Text
nodeStatuses ns =
  Map.fromList
    [ (NodeId (fromSqlKey k), pack (M.unNodeStatusKey (M.nodeNodeStatusId e)))
    | Entity k e <- ns
    ]

statusClass :: Text -> Maybe Text
statusClass st
  | T.null token = Nothing
  | otherwise = Just ("status-" <> token)
  where
    token = slug st

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

toLayoutEdge :: Entity M.Dependency -> LayoutEdge
toLayoutEdge (Entity k e) =
  dependsOn
    (EdgeId (fromSqlKey k))
    (NodeId (fromSqlKey (M.dependencyToNodeId e)))
    (NodeId (fromSqlKey (M.dependencyNodeId e)))

data FrameBox = FrameBox
  { fbMinX :: Double
  , fbMinY :: Double
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

polyline :: [Point] -> [Point] -> Text
polyline _ [] = ""
polyline jumps (p : ps) =
  "M" <> point p <> mconcat (zipWith run (p : ps) ps)
  where
    point (Point x y) = dblText x <> "," <> dblText y

    run (Point x0 y0) q@(Point x1 y1)
      | y0 /= y1 || null hops = " L" <> point q
      | otherwise = mconcat (map hop hops) <> " L" <> point q
      where
        rightward = x1 > x0

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
            <> (if rightward then "1 " else "0 ")
            <> point (Point (jx + dir * r) y0)
          where
            dir = if rightward then 1 else -1

    r = cfgJumpRadius defaultLayoutConfig

nodeGroup :: ServerGraph -> PlacedNode -> Html ()
nodeGroup sg n =
  g_
    [ id_ ("node-" <> nid)
    , dataNodeId_ nid
    , class_ "node"
    , transform_ ("translate(" <> dblText (ptX tl) <> "," <> dblText (ptY tl) <> ")")
    , hxGet_ (nodePanelLink rawId pid)
    , hxTrigger_ "click"
    , hxTarget_ "#node-panel"
    , hxPushUrl'_ (pushUrl rawId pid)
    , hxSwap_ "innerHTML"
    ]
    $ do
      rect_
        [ class_ shapeClass
        , width_ (dblText (szW sz))
        , height_ (dblText (szH sz))
        , rx_ "6"
        ]
        (mempty :: Html ())
      nodeLabel nid sz (pnLines n)

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
    shapeClass =
      T.unwords
        . (kindClass (pnKind n) :)
        . maybe [] pure
        $ Map.lookup (pnId n) (sgStatuses sg) >>= statusClass

kindClass :: NodeKind -> Text
kindClass RootNode = "root"
kindClass WorkNode = "work"

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
    , dy_ "0.35em"
    ]
    $ tspanLines ls

dblText :: Double -> Text
dblText v
  | v == fromIntegral rounded = intToText rounded
  | otherwise = pack (show v)
  where
    rounded = round v :: Int
