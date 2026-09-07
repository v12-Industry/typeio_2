module Domain.Project.Graph.LayoutSpec (spec) where

import Data.List (find, nub)
import Data.Maybe (fromJust, isJust, mapMaybe)
import qualified Data.Text as T
import Domain.Project.Graph.Layout (layout)
import Domain.Project.Graph.Types
import Test.Hspec

cfg :: LayoutConfig
cfg = defaultLayoutConfig

node :: Int -> LayoutNode
node n = LayoutNode (NodeId (fromIntegral n)) WorkNode (T.pack ("node " <> show n))

rootNode :: Int -> LayoutNode
rootNode n = (node n) {lnKind = RootNode}

-- | @dep i a b@: @b@ depends on @a@, so @a@ must finish first.
dep :: Int -> Int -> Int -> LayoutEdge
dep i a b =
  dependsOn
    (EdgeId (fromIntegral i))
    (NodeId (fromIntegral a))
    (NodeId (fromIntegral b))

-- | @holds i a b@: @a@ contains @b@, so @a@ is drawn above it.
holds :: Int -> Int -> Int -> LayoutEdge
holds i a b =
  contains
    (EdgeId (fromIntegral i))
    (NodeId (fromIntegral a))
    (NodeId (fromIntegral b))

placed :: Diagram -> Int -> PlacedNode
placed d n =
  fromJust (find ((== NodeId (fromIntegral n)) . pnId) (diagramNodes d))

topOf :: PlacedNode -> Double
topOf = ptY . pnTopLeft

centreX :: PlacedNode -> Double
centreX p = ptX (pnTopLeft p) + szW (pnSize p) / 2

-- | Do two placed boxes overlap in both axes?
overlaps :: PlacedNode -> PlacedNode -> Bool
overlaps a b = ov ptX szW && ov ptY szH
  where
    ov coord dim =
      coord (pnTopLeft a) < coord (pnTopLeft b) + dim (pnSize b)
        && coord (pnTopLeft b) < coord (pnTopLeft a) + dim (pnSize a)

{- | Every segment of an edge that passes through the interior of some
node's box.
-}
crossings :: Diagram -> PlacedEdge -> [(NodeId, Point, Point)]
crossings d e =
  [ (pnId n, a, b)
  | (a, b) <- zip (pePoints e) (drop 1 (pePoints e))
  , n <- diagramNodes d
  , let Point nx ny = pnTopLeft n
  , let Size nw nh = pnSize n
  , min (ptX a) (ptX b) < nx + nw
  , nx < max (ptX a) (ptX b)
  , min (ptY a) (ptY b) < ny + nh
  , ny < max (ptY a) (ptY b)
  ]

pairs :: [a] -> [(a, a)]
pairs xs = [(a, b) | (i, a) <- zip [0 :: Int ..] xs, (j, b) <- zip [0 ..] xs, i < j]

spec :: Spec
spec = do
  describe "layout" $ do
    it "places every node exactly once" $ do
      let d = layout cfg [node 1, node 2, node 3] [dep 10 2 1]
      map pnId (diagramNodes d)
        `shouldBe` [NodeId 1, NodeId 2, NodeId 3]

    it "never overlaps two node boxes" $ do
      let ns = map node [1 .. 6]
          es = [dep 10 2 1, dep 11 3 1, dep 12 4 2, dep 13 5 2, dep 14 6 3]
          d = layout cfg ns es
      filter (uncurry overlaps) (pairs (diagramNodes d)) `shouldBe` []

    it "draws a dependency below the node that depends on it" $ do
      let d = layout cfg [node 1, node 2] [dep 10 2 1]
      topOf (placed d 2) `shouldSatisfy` (> topOf (placed d 1))

    it "puts the project root in the top row" $ do
      let d = layout cfg [rootNode 1, node 2, node 3] [dep 10 2 1, dep 11 3 2]
          tops = map topOf (diagramNodes d)
      topOf (placed d 1) `shouldBe` minimum tops

    it "ends each edge on the dependent, which is where the arrowhead goes" $ do
      let d = layout cfg [node 1, node 2] [dep 10 2 1]
          e = head (diagramEdges d)
          lastPoint = last (pePoints e)
          dependentBox = placed d 1
      -- The final point lies on the dependent's box, not the dependency's.
      ptY lastPoint
        `shouldSatisfy` \y ->
          y >= topOf dependentBox
            && y <= topOf dependentBox + szH (pnSize dependentBox)

    it "routes every edge orthogonally, with at most two bends" $ do
      let d = layout cfg [node 1, node 2, node 3] [dep 10 2 1, dep 11 3 1]
          segments e = zip (pePoints e) (drop 1 (pePoints e))
          axisAligned (a, b) = ptX a == ptX b || ptY a == ptY b
      all (all axisAligned . segments) (diagramEdges d) `shouldBe` True
      all ((<= 4) . length . pePoints) (diagramEdges d) `shouldBe` True

    it "centres a node over the two it depends on (reference image 1)" $ do
      -- 1 depends on 2 and 3, so 1 is drawn above both and centred.
      let d = layout cfg [node 1, node 2, node 3] [dep 10 2 1, dep 11 3 1]
      centreX (placed d 1)
        `shouldBe` (centreX (placed d 2) + centreX (placed d 3)) / 2

    it "keeps a single-dependency chain colinear (reference image 2)" $ do
      let d = layout cfg [node 1, node 2, node 3] [dep 10 2 1, dep 11 3 2]
      map (centreX . placed d) [1, 2, 3]
        `shouldSatisfy` \[a, b, c] -> a == b && b == c

    it "reports bounds that contain every node box" $ do
      let d = layout cfg (map node [1 .. 4]) [dep 10 2 1, dep 11 3 1, dep 12 4 3]
          Bounds mn mx = diagramBounds d
          within p =
            ptX (pnTopLeft p) >= ptX mn
              && ptY (pnTopLeft p) >= ptY mn
              && ptX (pnTopLeft p) + szW (pnSize p) <= ptX mx
              && ptY (pnTopLeft p) + szH (pnSize p) <= ptY mx
      all within (diagramNodes d) `shouldBe` True

    it "anchors on the project root when there is one" $ do
      let d = layout cfg [rootNode 1, node 2] [dep 10 2 1]
      diagramRootAnchor d `shouldSatisfy` isJust

    it "has no anchor when no node is a project root" $ do
      let d = layout cfg [node 1, node 2] [dep 10 2 1]
      diagramRootAnchor d `shouldBe` Nothing

    it "wraps labels to the configured box" $ do
      let long = T.pack (replicate 200 'a')
          d = layout cfg [(node 1) {lnLabel = long}] []
          ls = pnLines (placed d 1)
      length ls `shouldSatisfy` (<= cfgLabelLines cfg)
      all ((<= cfgLabelWidth cfg) . T.length) ls `shouldBe` True

    it "produces a diagram for a cyclic graph rather than failing" $ do
      let ns = map node [1 .. 3]
          es = [dep 10 2 1, dep 11 3 2, dep 12 1 3]
          d = layout cfg ns es
      length (diagramNodes d) `shouldBe` 3
      length (mapMaybe (Just . peId) (diagramEdges d)) `shouldBe` 3

    it "marks the edge that was reversed to break a cycle" $ do
      let d = layout cfg (map node [1 .. 2]) [dep 10 2 1, dep 11 1 2]
      length (filter peReversed (diagramEdges d)) `shouldBe` 1

    it "never routes an edge through a node box" $ do
      -- The guarantee dummy nodes exist to provide: a multi-row edge
      -- travels in its own reserved lane rather than across whatever
      -- happens to sit in the rows it passes.
      let ns = map node [1 .. 6]
          -- A chain 1..5, plus a long edge from 1 straight down to 5.
          es =
            [ dep 10 2 1
            , dep 11 3 2
            , dep 12 4 3
            , dep 13 5 4
            , dep 14 5 1
            , dep 15 6 1
            ]
          d = layout cfg ns es
      concatMap (crossings d) (diagramEdges d) `shouldBe` []

    it "keeps a multi-row edge in one straight lane" $ do
      let ns = map node [1 .. 4]
          es = [dep 10 2 1, dep 11 3 2, dep 12 4 3, dep 13 4 1]
          d = layout cfg ns es
          long = head (filter ((== EdgeId 13) . peId) (diagramEdges d))
          columns = nub (map ptX (pePoints long))
      -- It spans three rows. A staircase would step across a new x in
      -- every one of them; holding the dummy chain's line means the
      -- edge only ever occupies three: the port it leaves, the lane it
      -- travels down, and the port it arrives at.
      length columns `shouldSatisfy` (<= 3)

    it "emits no element for a dummy node" $ do
      let ns = map node [1 .. 4]
          es = [dep 10 2 1, dep 11 3 2, dep 12 4 3, dep 13 4 1]
          d = layout cfg ns es
      -- Four real nodes in, four placed nodes out: the dummies the long
      -- edge routes through never reach the diagram.
      length (diagramNodes d) `shouldBe` 4

    it "handles an empty graph" $ do
      let d = layout cfg [] []
      diagramNodes d `shouldBe` []
      diagramEdges d `shouldBe` []

    it "is deterministic" $ do
      let ns = map node [1 .. 5]
          es = [dep 10 2 1, dep 11 3 1, dep 12 4 2, dep 13 5 3]
      layout cfg ns es `shouldBe` layout cfg ns es

  jumpSpec
  overlapSpec
  containmentSpec
  packingSpec

{- | Disconnected components are drawn side by side, not through each
other.

The fixture below is what packing them left to right by bounding box
buys: without it, a component one node wide at the top and four wide
two rows down spreads out underneath its neighbour, and the neighbour
ends up inside its span — two independent graphs drawn as one tangle.
-}
packingSpec :: Spec
packingSpec = describe "layout, component packing" $ do
  let ns = map node [1 .. 8]
      es =
        [ dep 10 3 1
        , dep 11 5 3
        , dep 12 6 3
        , dep 13 7 3
        , dep 14 8 3
        , dep 15 4 2
        ]
      -- A is the wide one; B is the two-node chain beside it.
      compA = [1, 3, 5, 6, 7, 8]
      compB = [2, 4]
      extentOf d g =
        ( minimum [ptX (pnTopLeft (placed d n)) | n <- g]
        , maximum
            [ ptX (pnTopLeft (placed d n)) + szW (pnSize (placed d n))
            | n <- g
            ]
        )

  it "keeps one component from being drawn inside another's span" $ do
    let d = layout cfg ns es
        (aLo, aHi) = extentOf d compA
        (bLo, bHi) = extentOf d compB
    (aLo < bHi && bLo < aHi) `shouldBe` False

  it "still overlaps no two node boxes" $ do
    let d = layout cfg ns es
    filter (uncurry overlaps) (pairs (diagramNodes d)) `shouldBe` []

  it "leaves a single-component graph alone" $ do
    -- A project with a root is one component, so packing is a no-op and
    -- the root stays centred over the work it holds.
    let d = layout cfg [rootNode 1, node 2, node 3] [holds 10 1 2, holds 11 1 3]
    centreX (placed d 1)
      `shouldBe` (centreX (placed d 2) + centreX (placed d 3)) / 2

{- | The project root heads the graph because it /contains/ its work.

Store membership as a @project.dependency@ row per node pointing at the
root and it does the opposite: layering correctly draws each dependent
above what it waits on, and so the root sinks beneath everything in the
project. The layout rule is not what breaks; the relationship it is
handed is.

These pin the distinction: containment puts the container above, a
dependency puts the dependent above, and a graph with both still gets
each right.
-}
containmentSpec :: Spec
containmentSpec = describe "layout, containment" $ do
  it "draws the container above what it contains" $ do
    let d = layout cfg [rootNode 1, node 2, node 3] [holds 10 1 2, holds 11 1 3]
    topOf (placed d 1) `shouldBe` minimum (map topOf (diagramNodes d))

  it "puts the root at the head of a project of plain work nodes" $ do
    -- The shape the app actually produces: a root plus work nodes that
    -- depend on nothing, related to it only by membership.
    let ns = rootNode 1 : map node [2 .. 5]
        d = layout cfg ns [holds (10 + i) 1 i | i <- [2 .. 5]]
    topOf (placed d 1) `shouldSatisfy` (< minimum (map (topOf . placed d) [2 .. 5]))

  it "still draws a dependent above what it waits on" $ do
    -- Containment must not have inverted ordinary dependencies on its
    -- way past: 3 waits on 2, so 3 stays above 2.
    let d =
          layout
            cfg
            [rootNode 1, node 2, node 3]
            [holds 10 1 2, holds 11 1 3, dep 12 2 3]
    topOf (placed d 3) `shouldSatisfy` (< topOf (placed d 2))
    topOf (placed d 1) `shouldBe` minimum (map topOf (diagramNodes d))

  it "tags each edge with where it came from" $ do
    -- Both kinds render identically; the tag records provenance, which
    -- is what tells a derived edge from one with a row behind it.
    let d = layout cfg [rootNode 1, node 2, node 3] [holds 10 1 2, dep 11 2 3]
        kindOf i = peKind (head (filter ((== EdgeId i) . peId) (diagramEdges d)))
    kindOf 10 `shouldBe` Contains
    kindOf 11 `shouldBe` DependsOn

  it "ends a containment edge on the root, where its arrowhead goes" $ do
    -- The project is what waits on the work, so the head belongs on the
    -- root end. Geometry has to agree with that, or the arrowhead
    -- points the wrong way.
    let d = layout cfg [rootNode 1, node 2] [holds 10 1 2]
        e = head (diagramEdges d)
        rootBox = placed d 1
        lastY = ptY (last (pePoints e))
    lastY
      `shouldSatisfy` \y ->
        y >= topOf rootBox && y <= topOf rootBox + szH (pnSize rootBox)

{- | No two edges drawn on top of each other.

Distinct from the crossing count in "Domain.Project.Graph.OrderSpec":
a crossing is two edges meeting at a point, which is expected and is
what line jumps annotate. This is two edges sharing a *stretch* of the
same line, which renders as one edge and is never correct.
-}
overlapSpec :: Spec
overlapSpec = describe "layout, edge overlap" $ do
  -- K(2,2): both top nodes depend on both bottom ones. The fixture from
  -- the ticket, and the shape that proves reordering tracks can't fix
  -- this -- the two middle edges swap columns, so each would need its
  -- track above the other's.
  let k22 =
        layout
          cfg
          (map node [1 .. 4])
          [dep 10 3 1, dep 11 4 1, dep 12 3 2, dep 13 4 2]

  it "draws no two edges on top of each other on K(2,2)" $
    collinearOverlaps k22 `shouldBe` []

  it "keeps every segment axis-aligned while separating them" $ do
    let axisAligned (Point x1 y1, Point x2 y2) = x1 == x2 || y1 == y2
    all (all axisAligned . runsOf) (diagramEdges k22) `shouldBe` True

  it "still routes no edge through a node box" $
    concatMap (crossings k22) (diagramEdges k22) `shouldBe` []

  it "leaves a graph with nothing to separate untouched" $ do
    let d = layout cfg (map node [1 .. 3]) [dep 10 2 1, dep 11 3 1]
    collinearOverlaps d `shouldBe` []

runsOf :: PlacedEdge -> [(Point, Point)]
runsOf e = zip (pePoints e) (drop 1 (pePoints e))

{- | Every pair of segments from *different* edges that lie on the same
line and share more than a point of it.

Touching at a single point is fine — that is two edges meeting, which
happens legitimately at a shared track. Sharing an interval is the bug.
-}
collinearOverlaps :: Diagram -> [(Run, Run)]
collinearOverlaps d =
  [ (s1, s2)
  | (i, e1) <- zip [0 :: Int ..] (diagramEdges d)
  , (j, e2) <- zip [0 ..] (diagramEdges d)
  , i < j
  , s1 <- spans e1
  , s2 <- spans e2
  , overlapping s1 s2
  ]
  where
    spans e = concatMap spanOfRun (runsOf e)
    spanOfRun (Point x1 y1, Point x2 y2)
      | x1 == x2 && y1 /= y2 = [Run Vertical x1 (min y1 y2) (max y1 y2)]
      | y1 == y2 && x1 /= x2 = [Run Horizontal y1 (min x1 x2) (max x1 x2)]
      | otherwise = []
    -- The axis has to be part of the comparison: without it a vertical
    -- at x=100 and a horizontal at y=100 would look collinear.
    overlapping (Run ax a lo1 hi1) (Run bx b lo2 hi2) =
      ax == bx && a == b && lo1 < hi2 && lo2 < hi1

data Axis = Vertical | Horizontal
  deriving (Eq, Show)

data Run = Run Axis Double Double Double
  deriving (Eq, Show)

{- | Line jumps through the whole pipeline.

"Domain.Project.Graph.RouteSpec" pins the jump geometry itself, on
hand-built polylines. This pins what that fixture cannot: that a real
graph, laid out and routed by the actual pipeline, still produces
crossings for it to mark. Shipping a correct jump-finder that never
fires would be an easy mistake, and this is what would catch it.
-}
jumpSpec :: Spec
jumpSpec = describe "layout, line jumps" $ do
  -- The smallest shape found whose routing the crossing-reduction
  -- sweeps cannot untangle into something planar.
  let crossing =
        layout
          cfg
          (map node [1 .. 5])
          [dep 10 3 1, dep 11 4 1, dep 12 4 2, dep 13 5 2, dep 14 5 1]

  it "marks a crossing in a graph whose routing genuinely has one" $
    sum (map (length . peJumps) (diagramEdges crossing))
      `shouldSatisfy` (> 0)

  it "leaves a graph that routes cleanly with no jumps" $ do
    let d = layout cfg (map node [1 .. 3]) [dep 10 2 1, dep 11 3 1]
    concatMap peJumps (diagramEdges d) `shouldBe` []

  it "puts every jump strictly inside a run of its own edge" $ do
    let onOwnRun e (Point jx jy) =
          or
            [ y0 == y1 && jy == y0 && jx > min x0 x1 && jx < max x0 x1
            | (Point x0 y0, Point x1 y1) <-
                zip (pePoints e) (drop 1 (pePoints e))
            ]
    all
      (\e -> all (onOwnRun e) (peJumps e))
      (diagramEdges crossing)
      `shouldBe` True
