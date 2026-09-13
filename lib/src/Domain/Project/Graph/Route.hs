{-# LANGUAGE ScopedTypeVariables #-}

module Domain.Project.Graph.Route
  ( Routed (..)
  , routeEdges
  , addJumps
  ) where

import Data.Foldable (foldl')
import Data.List (sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Domain.Project.Graph.Layer (Segment (..))
import Domain.Project.Graph.Types

data Routed = Routed
  { routedEdges :: [PlacedEdge]
  , routedLayerTops :: Map Int Double
  }
  deriving (Eq, Show)

routeEdges ::
  LayoutConfig ->
  Map LNode Int ->
  Map LNode Double ->
  [Segment] ->
  Map EdgeId [LNode] ->
  Routed
routeEdges cfg layers centres segments chains =
  Routed
    { routedEdges = addJumps (map polyline (M.toAscList chains))
    , routedLayerTops = layerTops
    }
  where
    Size nodeW nodeH = cfgNodeSize cfg
    layerOf n = M.findWithDefault 0 n layers
    centreOf n = M.findWithDefault 0 n centres

    reversedOf = M.fromList [(segEdge s, segReversed s) | s <- segments]
    kindOf = M.fromList [(segEdge s, segKind s) | s <- segments]

    portsOn ownerOf otherOf =
      M.fromList
        [ (segEdge s, (owner, slot, total))
        | (owner, ss) <- M.toList grouped
        , not (isDummy owner)
        , let ordered = sortOn (\x -> (centreOf (otherOf x), segEdge x)) ss
        , let total = length ordered
        , (slot, s) <- zip [1 :: Int ..] ordered
        ]
      where
        grouped = M.fromListWith (++) [(ownerOf s, [s]) | s <- segments]

    bottomPorts = portsOn segFrom segTo
    topPorts = portsOn segTo segFrom

    portX ports fallback s =
      case M.lookup (segEdge s) ports of
        Just (owner, slot, total)
          | not (isDummy (fallback s)) ->
              centreOf owner
                - nodeW / 2
                + nodeW * fromIntegral slot / fromIntegral (total + 1)
        _ -> centreOf (fallback s)

    upperX s = portX bottomPorts segFrom s
    rawLowerX s = portX topPorts segTo s

    upperColumns :: Map Int (Set Double)
    upperColumns =
      M.fromListWith
        (<>)
        [(gapOf s, S.singleton (upperX s)) | s <- segments]

    nudgeStep s =
      case M.lookup (segEdge s) topPorts of
        Just (_, _, total) -> nodeW / fromIntegral (total + 1) / 3
        Nothing -> cfgDummyWidth cfg / 3

    lowerX s
      | ux == raw = raw
      | otherwise = clear raw
      where
        ux = upperX s
        raw = rawLowerX s
        claimed = M.findWithDefault S.empty (gapOf s) upperColumns
        step = max 1e-9 (nudgeStep s)
        clear x
          | x `S.member` claimed = clear (x + step)
          | otherwise = x

    needsTrack s = upperX s /= lowerX s
    spanOf s = (min (upperX s) (lowerX s), max (upperX s) (lowerX s))
    gapOf s = layerOf (segFrom s)

    byGap = M.fromListWith (++) [(gapOf s, [s]) | s <- segments, needsTrack s]

    tracksIn :: [Segment] -> (Map EdgeId Int, Map Int [(Double, Double)])
    tracksIn ss = foldl' place (M.empty, M.empty) ordered
      where
        ordered = sortOn (\s -> (spanOf s, segEdge s)) ss
        place (assigned, occupied) s =
          let t = firstFree 0
              firstFree i
                | any (overlaps (spanOf s)) (M.findWithDefault [] i occupied) = firstFree (i + 1)
                | otherwise = i
           in (M.insert (segEdge s) t assigned, M.insertWith (++) t [spanOf s] occupied)
        overlaps (a1, b1) (a2, b2) = a1 < b2 && a2 < b1

    gapTracks = M.map tracksIn byGap
    trackOf s =
      case M.lookup (gapOf s) gapTracks of
        Just (assigned, _) -> M.findWithDefault 0 (segEdge s) assigned
        Nothing -> 0
    trackCount g =
      case M.lookup g gapTracks of
        Just (_, occupied) -> M.size occupied
        Nothing -> 0

    gapHeight g =
      max
        (cfgLayerGap cfg)
        (fromIntegral (trackCount g + 1) * cfgTrackGap cfg)

    lastLayer = if M.null layers then 0 else maximum (M.elems layers)
    layerTops =
      M.fromList (zip [0 ..] (scanl step (cfgMargin cfg) [0 .. lastLayer - 1]))
      where
        step y g = y + nodeH + gapHeight g

    topOf l = M.findWithDefault (cfgMargin cfg) l layerTops
    trackY s =
      let g = gapOf s
          gapTop = topOf g + nodeH
          slots = fromIntegral (trackCount g + 1)
       in gapTop + gapHeight g * (fromIntegral (trackOf s) + 1) / slots

    exitY n
      | isDummy n = topOf (layerOf n) + nodeH
      | otherwise = topOf (layerOf n) + nodeH
    entryY n = topOf (layerOf n)

    segmentPoints s
      | ux == lx = [Point ux (exitY (segFrom s)), Point lx (entryY (segTo s))]
      | otherwise =
          [ Point ux (exitY (segFrom s))
          , Point ux (trackY s)
          , Point lx (trackY s)
          , Point lx (entryY (segTo s))
          ]
      where
        ux = upperX s
        lx = lowerX s

    segmentsFor e = sortOn (layerOf . segFrom) (filter ((== e) . segEdge) segments)

    polyline (e, _chain) =
      PlacedEdge
        { peId = e
        , peKind = M.findWithDefault DependsOn e kindOf
        , pePoints = orient (simplify (concatMap segmentPoints (segmentsFor e)))
        , peReversed = reversed
        , peJumps = []
        }
      where
        reversed = M.findWithDefault False e reversedOf

        orient ps
          | reversed = ps
          | otherwise = reverse ps

addJumps :: [PlacedEdge] -> [PlacedEdge]
addJumps es = map mark es
  where
    verticals =
      [ (peId e, x, min y1 y2, max y1 y2)
      | e <- es
      , (Point x y1, Point x' y2) <- runsOf e
      , x == x'
      , y1 /= y2
      ]

    mark e = e {peJumps = jumpsFor e}

    jumpsFor e =
      [ Point vx hy
      | (Point x1 hy, Point x2 hy') <- runsOf e
      , hy == hy'
      , x1 /= x2
      , (vid, vx, vTop, vBot) <- verticals
      , vid /= peId e
      , strictlyBetween vx (min x1 x2) (max x1 x2)
      , strictlyBetween hy vTop vBot
      ]

    strictlyBetween v lo hi = v > lo && v < hi

    runsOf e = zip (pePoints e) (drop 1 (pePoints e))

simplify :: [Point] -> [Point]
simplify = collinear . dedupe
  where
    dedupe (p : q : rest)
      | p == q = dedupe (q : rest)
      | otherwise = p : dedupe (q : rest)
    dedupe ps = ps

    collinear (p : q : r : rest)
      | (ptX p == ptX q && ptX q == ptX r)
          || (ptY p == ptY q && ptY q == ptY r) =
          collinear (p : r : rest)
      | otherwise = p : collinear (q : r : rest)
    collinear ps = ps
