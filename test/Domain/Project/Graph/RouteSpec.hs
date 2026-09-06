module Domain.Project.Graph.RouteSpec (spec) where

import Data.List (nub, sort)
import qualified Data.Map.Strict as M
import Domain.Project.Graph.Layer (Segment (..))
import Domain.Project.Graph.Route (Routed (..), addJumps, routeEdges)
import Domain.Project.Graph.Types
import Test.Hspec

cfg :: LayoutConfig
cfg = defaultLayoutConfig

nid :: Int -> LNode
nid = Real . NodeId . fromIntegral

eid :: Int -> EdgeId
eid = EdgeId . fromIntegral

{- | @arc i a b@ puts @a@ in the row above @b@. Since 'breakCycles'
orients an ordinary edge dependent-above-dependency, @a@ here is the
dependent and @b@ the dependency.
-}
arc :: Int -> Int -> Int -> Segment
arc i a b = Segment (eid i) DependsOn (nid a) (nid b) False

layersOf :: [(Int, Int)] -> M.Map LNode Int
layersOf = M.fromList . map (\(n, l) -> (nid n, l))

centresOf :: [(Int, Double)] -> M.Map LNode Double
centresOf = M.fromList . map (\(n, x) -> (nid n, x))

{- | These fixtures are all single-segment edges, so each chain is just
the segment's two ends.
-}
chainsOf :: [Segment] -> M.Map EdgeId [LNode]
chainsOf ss = M.fromList [(segEdge s, [segFrom s, segTo s]) | s <- ss]

route :: M.Map LNode Int -> M.Map LNode Double -> [Segment] -> Routed
route ls cs ss = routeEdges cfg ls cs ss (chainsOf ss)

edgeById :: Routed -> Int -> PlacedEdge
edgeById r i = head (filter ((== eid i) . peId) (routedEdges r))

segments :: PlacedEdge -> [(Point, Point)]
segments e = zip (pePoints e) (drop 1 (pePoints e))

axisAligned :: (Point, Point) -> Bool
axisAligned (a, b) = ptX a == ptX b || ptY a == ptY b

horizontals :: PlacedEdge -> [(Double, Double, Double)]
horizontals e =
  [ (ptY a, min (ptX a) (ptX b), max (ptX a) (ptX b))
  | (a, b) <- segments e
  , ptY a == ptY b
  , ptX a /= ptX b
  ]

overlap :: (Double, Double, Double) -> (Double, Double, Double) -> Bool
overlap (y1, a1, b1) (y2, a2, b2) = y1 == y2 && a1 < b2 && a2 < b1

pairs :: [a] -> [(a, a)]
pairs xs = [(a, b) | (i, a) <- zip [0 :: Int ..] xs, (j, b) <- zip [0 ..] xs, i < j]

spec :: Spec
spec = do
  jumpSpec
  describe "routeEdges" $ do
    it "emits only axis-aligned segments" $ do
      let r =
            route
              (layersOf [(1, 0), (2, 1), (3, 1)])
              (centresOf [(1, 200), (2, 0), (3, 400)])
              [arc 10 1 2, arc 11 1 3]
      all (all axisAligned . segments) (routedEdges r) `shouldBe` True

    it "uses at most two bends per edge" $ do
      let r =
            route
              (layersOf [(1, 0), (2, 1)])
              (centresOf [(1, 0), (2, 400)])
              [arc 10 1 2]
      length (pePoints (edgeById r 10)) `shouldBe` 4

    it "draws a straight line when the ports already line up" $ do
      let r =
            route
              (layersOf [(1, 0), (2, 1)])
              (centresOf [(1, 200), (2, 200)])
              [arc 10 1 2]
      length (pePoints (edgeById r 10)) `shouldBe` 2

    it "gives edges into the same node distinct ports" $ do
      -- Three dependencies feeding one dependent: reference image 5
      -- shows three separate arrowheads on one node's top edge.
      let r =
            route
              (layersOf [(1, 0), (2, 1), (3, 1), (4, 1)])
              (centresOf [(1, 200), (2, 0), (3, 200), (4, 400)])
              [arc 10 1 2, arc 11 1 3, arc 12 1 4]
          arrivals = [ptX (last (pePoints e)) | e <- routedEdges r]
      length (nub arrivals) `shouldBe` 3

    it "gives edges out of the same node distinct ports" $ do
      let r =
            route
              (layersOf [(1, 0), (2, 1), (3, 1)])
              (centresOf [(1, 200), (2, 0), (3, 400)])
              [arc 10 1 2, arc 11 1 3]
          departures = [ptX (head (pePoints e)) | e <- routedEdges r]
      length (nub departures) `shouldBe` 2

    it "never overlaps two horizontal runs collinearly" $ do
      let r =
            route
              (layersOf [(1, 0), (2, 0), (3, 1), (4, 1)])
              (centresOf [(1, 0), (2, 600), (3, 600), (4, 0)])
              [arc 10 1 3, arc 11 2 4]
          runs = concatMap horizontals (routedEdges r)
      filter (uncurry overlap) (pairs runs) `shouldBe` []

    it "shares one track between runs that do not overlap" $ do
      -- Two edges far apart horizontally have no reason to stack.
      let r =
            route
              (layersOf [(1, 0), (2, 0), (3, 1), (4, 1)])
              (centresOf [(1, 0), (2, 1000), (3, 200), (4, 1200)])
              [arc 10 1 3, arc 11 2 4]
          ys = nub [y | (y, _, _) <- concatMap horizontals (routedEdges r)]
      length ys `shouldBe` 1

    it "keeps every horizontal run strictly between the two rows" $ do
      let layers = layersOf [(1, 0), (2, 1), (3, 1)]
          r =
            route
              layers
              (centresOf [(1, 200), (2, 0), (3, 400)])
              [arc 10 1 2, arc 11 1 3]
          tops = routedLayerTops r
          rowTop l = M.findWithDefault 0 l tops
          nodeH = szH (cfgNodeSize cfg)
          runs = concatMap horizontals (routedEdges r)
      all (\(y, _, _) -> y > rowTop 0 + nodeH && y < rowTop 1) runs
        `shouldBe` True

    it "grows a gap that has to carry many tracks" $ do
      -- Six edges all crossing the same span cannot share tracks, so
      -- the gap has to open up past the default.
      let wide n = [arc (10 + i) i (100 + i) | i <- [1 .. n]]
          layers n =
            layersOf ([(i, 0) | i <- [1 .. n]] <> [(100 + i, 1) | i <- [1 .. n]])
          centres n =
            centresOf
              ( [(i, fromIntegral i * 200) | i <- [1 .. n]]
                  <> [(100 + i, fromIntegral (n - i) * 200) | i <- [1 .. n]]
              )
          gapFor n =
            let r = route (layers n) (centres n) (wide n)
                tops = routedLayerTops r
             in M.findWithDefault 0 1 tops - M.findWithDefault 0 0 tops
      gapFor 6 `shouldSatisfy` (> gapFor 1)

    it "ends an ordinary edge on the dependent, above its dependency" $ do
      let r =
            route
              (layersOf [(1, 0), (2, 1)])
              (centresOf [(1, 200), (2, 200)])
              [arc 10 1 2]
          e = edgeById r 10
      -- Arrowhead (last point) is the higher one: dependency -> dependent.
      ptY (last (pePoints e)) `shouldSatisfy` (< ptY (head (pePoints e)))

    it "points a reversed edge the other way, since the arrow follows the data" $ do
      let r =
            route
              (layersOf [(1, 0), (2, 1)])
              (centresOf [(1, 200), (2, 200)])
              [(arc 10 1 2) {segReversed = True}]
          e = edgeById r 10
      ptY (last (pePoints e)) `shouldSatisfy` (> ptY (head (pePoints e)))

    it "is deterministic" $ do
      let go =
            route
              (layersOf [(1, 0), (2, 1), (3, 1)])
              (centresOf [(1, 200), (2, 0), (3, 400)])
              [arc 10 1 2, arc 11 1 3]
      routedEdges go `shouldBe` routedEdges go
      routedLayerTops go `shouldBe` routedLayerTops go

    it "handles a graph with no edges" $ do
      let r = route (layersOf [(1, 0)]) (centresOf [(1, 0)]) []
      routedEdges r `shouldBe` []
      sort (M.keys (routedLayerTops r)) `shouldBe` [0]

-- Line jumps. These use `addJumps` on hand-built polylines
-- rather than driving `routeEdges`: the property under test is pure
-- segment geometry, and a fixture that states its own crossing is a far
-- clearer statement of intent than a graph contrived to produce one.
-- The last case checks the wiring through the real router.
placed :: Int -> [(Double, Double)] -> PlacedEdge
placed i pts =
  PlacedEdge
    { peId = eid i
    , pePoints = [Point x y | (x, y) <- pts]
    , peReversed = False
    , peJumps = []
    }

jumpsOf :: Int -> [PlacedEdge] -> [Point]
jumpsOf i es =
  concat [peJumps e | e <- es, peId e == eid i]

jumpSpec :: Spec
jumpSpec = describe "addJumps" $ do
  it "marks a horizontal run where a vertical one crosses it" $ do
    -- A horizontal run at y=50 from x=0..100, and a vertical run at
    -- x=50 from y=0..100. They cross at (50,50).
    let es =
          addJumps
            [ placed 10 [(0, 50), (100, 50)]
            , placed 11 [(50, 0), (50, 100)]
            ]
    jumpsOf 10 es `shouldBe` [Point 50 50]

  it "puts the jump on the horizontal side only" $ do
    let es =
          addJumps
            [ placed 10 [(0, 50), (100, 50)]
            , placed 11 [(50, 0), (50, 100)]
            ]
    -- Hopping both would put two arcs at one point and restore the
    -- ambiguity the hop exists to remove.
    jumpsOf 11 es `shouldBe` []

  it "draws no jump where two edges merely meet at a shared port" $ do
    -- Both runs touch (100,50): the horizontal ends there and the
    -- vertical starts there. That is a junction, not a crossing.
    let es =
          addJumps
            [ placed 10 [(0, 50), (100, 50)]
            , placed 11 [(100, 50), (100, 150)]
            ]
    jumpsOf 10 es `shouldBe` []
    jumpsOf 11 es `shouldBe` []

  it "draws no jump where a vertical only touches the end of a run" $ do
    -- Endpoint-on-endpoint is covered above; this is the vertical's own
    -- endpoint landing partway along the horizontal, which is still a
    -- T-junction rather than a crossing.
    let es =
          addJumps
            [ placed 10 [(0, 50), (100, 50)]
            , placed 11 [(50, 50), (50, 150)]
            ]
    jumpsOf 10 es `shouldBe` []

  it "ignores an edge's own corners" $ do
    -- One edge, two bends: its horizontal run meets its own verticals
    -- at both ends. Those are corners, and an edge never hops itself.
    let es = addJumps [placed 10 [(0, 0), (0, 50), (100, 50), (100, 100)]]
    jumpsOf 10 es `shouldBe` []

  it "marks every crossing on a run that is crossed more than once" $ do
    let es =
          addJumps
            [ placed 10 [(0, 50), (200, 50)]
            , placed 11 [(50, 0), (50, 100)]
            , placed 12 [(150, 0), (150, 100)]
            ]
    sort (map ptX (jumpsOf 10 es)) `shouldBe` [50, 150]

  it "leaves an uncrossed graph with no jumps at all" $ do
    let r =
          route
            (layersOf [(1, 0), (2, 1)])
            (centresOf [(1, 200), (2, 200)])
            [arc 10 1 2]
    concatMap peJumps (routedEdges r) `shouldBe` []
