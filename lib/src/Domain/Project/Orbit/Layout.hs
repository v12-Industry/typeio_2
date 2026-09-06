module Domain.Project.Orbit.Layout
  ( orbit
  , leafCount
  ) where

import Data.List (sort)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import Data.Text.Util (wrapLabel)
import Domain.Project.Orbit.Types
  ( Bounds (..)
  , Disc (..)
  , Link (..)
  , NodeId
  , OrbitConfig (..)
  , OrbitDiagram (..)
  , OrbitEdge
  , OrbitNode (..)
  , OrbitTree (..)
  , Point (..)
  )
import Domain.Project.Orbit.Unfold (unfold)

orbit :: OrbitConfig -> [OrbitNode] -> [OrbitEdge] -> OrbitDiagram
orbit cfg ns es =
  OrbitDiagram
    { odDiscs = placed
    , odLinks = links
    , odBounds = bounds cfg placed
    }
  where
    forest = unfold ns es
    labels = M.fromList [(onId n, onLabel n) | n <- ns]

    angled = angles forest
    radii = ringRadii cfg (length forest) angled
    placed = map (place cfg labels radii) (flattenAngled angled)
    links = concatMap (treeLinks cfg radii) angled

leafCount :: OrbitTree -> Int
leafCount t
  | null (otChildren t) = 1
  | otherwise = sum (map leafCount (otChildren t))

angles :: [OrbitTree] -> [Angled]
angles forest = snd (goMany (0 :: Int) forest)
  where
    total = max 1 (sum (map leafCount forest))
    slice = 2 * pi / fromIntegral total

    goMany i [] = (i, [])
    goMany i (t : rest) =
      let (i', a) = go i t
          (i'', as) = goMany i' rest
       in (i'', a : as)

    go i t = case otChildren t of
      [] ->
        ( i + 1
        , Angled t ((fromIntegral i + 0.5) * slice) []
        )
      kids ->
        let (i', as) = goMany i kids
            theta = sum (map anAngle as) / fromIntegral (length as)
         in (i', Angled t theta as)

data Angled = Angled
  { anTree :: OrbitTree
  , anAngle :: Double
  , anChildren :: [Angled]
  }

flattenAngled :: [Angled] -> [Angled]
flattenAngled = concatMap (\a -> a : flattenAngled (anChildren a))

ringRadii :: OrbitConfig -> Int -> [Angled] -> M.Map Int Double
ringRadii cfg treeCount as = foldl step M.empty [0 .. maxRing]
  where
    everyDisc = flattenAngled as
    maxRing =
      if null everyDisc
        then -1
        else maximum (map (otRing . anTree) everyDisc)

    singleHead = treeCount == 1

    step acc k = M.insert k r acc
      where
        ringStep = 2 * cfgDiscRadius cfg + cfgMinRingGap cfg
        prev = maybe start (+ ringStep) (M.lookup (k - 1) acc)
        start
          | singleHead = 0
          | otherwise = cfgEyeRadius cfg
        r = max prev (demand k)

    demand k = case minGapOn k of
      Nothing -> 0
      Just g
        | g <= 0 -> 0
        | otherwise -> (2 * cfgDiscRadius cfg + cfgDiscGap cfg) / g

    minGapOn k = case sort [anAngle a | a <- everyDisc, otRing (anTree a) == k] of
      [] -> Nothing
      [_] -> Nothing
      ts ->
        Just (minimum (zipWith (-) (tail ts) ts <> [2 * pi - (last ts - head ts)]))

place :: OrbitConfig -> M.Map NodeId T.Text -> M.Map Int Double -> Angled -> Disc
place cfg labels radii a =
  Disc
    { dNode = otNode t
    , dReplica = otReplica t
    , dRing = otRing t
    , dAngle = anAngle a
    , dCentre = polar (radiusOf radii (otRing t)) (anAngle a)
    , dLines =
        wrapLabel
          (cfgLabelWidth cfg)
          (cfgLabelLines cfg)
          (M.findWithDefault T.empty (otNode t) labels)
    }
  where
    t = anTree a

radiusOf :: M.Map Int Double -> Int -> Double
radiusOf radii k = fromMaybe 0 (M.lookup k radii)

polar :: Double -> Double -> Point
polar r theta = Point (r * sin theta) (negate (r * cos theta))

treeLinks :: OrbitConfig -> M.Map Int Double -> Angled -> [Link]
treeLinks cfg radii a =
  [ trim cfg (centre k) (centre a)
  | k <- anChildren a
  ]
    <> concatMap (treeLinks cfg radii) (anChildren a)
  where
    centre x = polar (radiusOf radii (otRing (anTree x))) (anAngle x)

trim :: OrbitConfig -> Point -> Point -> Link
trim cfg from to
  | dist <= 2 * r = Link from to
  | otherwise =
      Link
        (Point (ptX from + ux * r) (ptY from + uy * r))
        (Point (ptX to - ux * r) (ptY to - uy * r))
  where
    r = cfgDiscRadius cfg
    dx = ptX to - ptX from
    dy = ptY to - ptY from
    dist = sqrt (dx * dx + dy * dy)
    ux = if dist == 0 then 0 else dx / dist
    uy = if dist == 0 then 0 else dy / dist

bounds :: OrbitConfig -> [Disc] -> Bounds
bounds cfg ds
  | null ds = Bounds (Point 0 0) (Point 0 0)
  | otherwise =
      Bounds
        (Point (minimum xs - pad) (minimum ys - pad))
        (Point (maximum xs + pad) (maximum ys + pad))
  where
    pad = cfgDiscRadius cfg + cfgMargin cfg
    xs = map (ptX . dCentre) ds
    ys = map (ptY . dCentre) ds
