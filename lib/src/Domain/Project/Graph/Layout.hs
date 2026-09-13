module Domain.Project.Graph.Layout
  ( layout
  ) where

import Data.List (sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text.Util (wrapLabel)
import Domain.Project.Graph.Coord (assignX)
import Domain.Project.Graph.Layer (assignLayers, breakCycles, insertDummies)
import Domain.Project.Graph.Order (orderRows)
import Domain.Project.Graph.Route (Routed (..), routeEdges)
import Domain.Project.Graph.Types

layout :: LayoutConfig -> [LayoutNode] -> [LayoutEdge] -> Diagram
layout cfg ns es =
  Diagram
    { diagramNodes = placed
    , diagramEdges = routedEdges routed
    , diagramBounds = bounds
    , diagramRootAnchor = rootAnchor
    }
  where
    arcs = breakCycles ns es
    layers = assignLayers ns arcs

    (segments, slotLayers, chains) = insertDummies layers arcs

    rows :: Map Int [LNode]
    rows = orderRows seeded segments
    seeded =
      M.fromListWith
        (flip (<>))
        [(l, [n]) | (n, l) <- sortOn fst (M.toList slotLayers)]
    layerOf n = M.findWithDefault 0 (Real n) slotLayers

    Size nodeW _ = cfgNodeSize cfg
    margin = cfgMargin cfg

    widthOf n
      | isDummy n = cfgDummyWidth cfg
      | otherwise = nodeW

    rawCentres = assignX widthOf (cfgNodeGap cfg) rows segments
    realCentres = [x | (n, x) <- M.toList rawCentres, not (isDummy n)]
    shift
      | null realCentres = 0
      | otherwise = margin + nodeW / 2 - minimum realCentres
    centres = M.map (+ shift) rawCentres
    centreXOf n = M.findWithDefault (margin + nodeW / 2) (Real n) centres

    routed = routeEdges cfg slotLayers centres segments chains

    topLeftOf n =
      Point
        (centreXOf n - nodeW / 2)
        (M.findWithDefault margin (layerOf n) (routedLayerTops routed))

    placed =
      [ PlacedNode
          { pnId = lnId n
          , pnKind = lnKind n
          , pnLines = wrapLabel (cfgLabelWidth cfg) (cfgLabelLines cfg) (lnLabel n)
          , pnTopLeft = topLeftOf (lnId n)
          , pnSize = cfgNodeSize cfg
          }
      | n <- ns
      ]

    centreOf p =
      Point
        (ptX (pnTopLeft p) + szW (pnSize p) / 2)
        (ptY (pnTopLeft p) + szH (pnSize p) / 2)

    bounds
      | null placed = Bounds (Point 0 0) (Point (2 * margin) (2 * margin))
      | otherwise =
          Bounds
            (Point (minimum xs - margin) (minimum ys - margin))
            (Point (maximum xs' + margin) (maximum ys' + margin))
      where
        xs = map (ptX . pnTopLeft) placed
        ys = map (ptY . pnTopLeft) placed
        xs' = map (\p -> ptX (pnTopLeft p) + szW (pnSize p)) placed
        ys' = map (\p -> ptY (pnTopLeft p) + szH (pnSize p)) placed

    rootAnchor =
      case filter ((== RootNode) . pnKind) placed of
        (p : _) -> Just (centreOf p)
        [] -> Nothing
