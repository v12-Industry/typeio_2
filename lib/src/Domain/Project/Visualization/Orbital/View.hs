{-# LANGUAGE OverloadedStrings #-}

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

discGroup :: Int64 -> OrbitConfig -> Map NodeId Text -> Disc -> Html ()
discGroup pid cfg labels disc =
  g_
    [ id_ ("disc-" <> discKey)
    , dataNodeId_ nid
    , class_ "disc"
    , style_ ("--node-hue: " <> nodeHue rawId)
    , h_ $
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

    label = Map.findWithDefault T.empty (dNode disc) labels

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

nodeHue :: Int64 -> Text
nodeHue nodeId = dbl (fromIntegral thousandths / 1000)
  where
    thousandths = (nodeId * 137508) `mod` 360000

dbl :: Double -> Text
dbl x
  | x == fromIntegral (round x :: Int) = pack (show (round x :: Int))
  | otherwise = pack (show x)
