module Domain.Project.Orbit.LayoutSpec (spec) where

import Data.List (sort, tails)
import qualified Data.Text as T
import Domain.Project.Orbit.Layout (leafCount, orbit)
import Domain.Project.Orbit.Types
  ( Bounds (..)
  , Disc (..)
  , Link (..)
  , NodeId (..)
  , OrbitConfig (..)
  , OrbitDiagram (..)
  , OrbitEdge (..)
  , OrbitNode (..)
  , OrbitTree (..)
  , Point (..)
  , defaultOrbitConfig
  )
import Domain.Project.Orbit.Unfold (unfold)
import Test.Hspec

cfg :: OrbitConfig
cfg = defaultOrbitConfig

node :: Int -> OrbitNode
node n = OrbitNode (NodeId (fromIntegral n)) (T.pack ("node " <> show n))

-- | @dep a b@: @a@ depends on @b@, so @b@ must finish first.
dep :: Int -> Int -> OrbitEdge
dep a b = OrbitEdge (NodeId (fromIntegral a)) (NodeId (fromIntegral b))

-- | The worked example, as in @UnfoldSpec@: heads 1, 2, 6.
exampleNodes :: [OrbitNode]
exampleNodes = map node [1 .. 7]

exampleEdges :: [OrbitEdge]
exampleEdges =
  [dep 1 4, dep 4 5, dep 2 3, dep 3 5, dep 6 7, dep 6 3]

drawing :: OrbitDiagram
drawing = orbit cfg exampleNodes exampleEdges

dist :: Point -> Point -> Double
dist (Point x1 y1) (Point x2 y2) = sqrt (dx * dx + dy * dy)
  where
    dx = x2 - x1
    dy = y2 - y1

radiusOf :: Disc -> Double
radiusOf d = dist (Point 0 0) (dCentre d)

pairs :: [a] -> [(a, a)]
pairs xs = [(a, b) | (a : rest) <- tails xs, b <- rest]

{- | Whether two open segments properly cross.

Endpoint contact does not count: links that meet at a shared disc touch
at the rim by construction, and that is a junction rather than a
crossing.
-}
crosses :: Link -> Link -> Bool
crosses (Link p1 p2) (Link p3 p4) =
  case (d1 * d2 < 0, d3 * d4 < 0) of
    (True, True) -> True
    _ -> False
  where
    side (Point ax ay) (Point bx by) (Point cx cy) =
      (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    d1 = side p3 p4 p1
    d2 = side p3 p4 p2
    d3 = side p1 p2 p3
    d4 = side p1 p2 p4

{- | Whether a link passes through a disc that is not one of its own
endpoints: the perpendicular distance from the centre to the segment,
compared against the disc's radius.
-}
passesThrough :: Double -> Point -> Link -> Bool
passesThrough r c (Link a b)
  | dist a c < 1e-6 || dist b c < 1e-6 = False
  | otherwise = nearest < r - 1e-6
  where
    dx = ptX b - ptX a
    dy = ptY b - ptY a
    len2 = dx * dx + dy * dy
    t
      | len2 == 0 = 0
      | otherwise =
          max 0 (min 1 (((ptX c - ptX a) * dx + (ptY c - ptY a) * dy) / len2))
    proj = Point (ptX a + t * dx) (ptY a + t * dy)
    nearest = dist proj c

spec :: Spec
spec = do
  describe "leafCount" $ do
    it "counts a lone disc as one leaf" $
      leafCount (OrbitTree (NodeId 1) 0 0 []) `shouldBe` 1

    it "counts the leaves of a subtree, not its discs" $ do
      let leaf n = OrbitTree (NodeId n) 0 1 []
          t = OrbitTree (NodeId 1) 0 0 [leaf 2, OrbitTree (NodeId 3) 0 1 [leaf 4]]
      leafCount t `shouldBe` 2

  describe "orbit, on the worked example" $ do
    it "places one disc per unfolded disc" $
      length (odDiscs drawing) `shouldBe` 10

    it "draws one link per parent-child pair" $
      -- Ten discs in three trees: every disc but the three heads hangs
      -- off exactly one parent.
      length (odLinks drawing) `shouldBe` 7

    it "never overlaps two discs" $
      let ds = odDiscs drawing
          minSep = 2 * cfgDiscRadius cfg
       in [() | (a, b) <- pairs ds, dist (dCentre a) (dCentre b) < minSep - 1e-6]
            `shouldBe` []

    it "never crosses two links" $
      -- The entire premise of this visualization. Asserted directly
      -- rather than argued from the construction, because if it ever
      -- stops holding the drawing has lost its only advantage over the
      -- layered one.
      [() | (a, b) <- pairs (odLinks drawing), crosses a b] `shouldBe` []

    it "gives every link a visible length" $
      -- Tangency is not overlap, so every overlap assertion passes on
      -- a drawing where `cfgMinRingGap` is read as a centre-to-centre
      -- distance: at a ring step of exactly one diameter, radially
      -- adjacent discs touch and the link between them is trimmed to
      -- nothing -- touching circles with no arrow at all. This is the
      -- assertion that catches that.
      [() | l <- odLinks drawing, dist (lFrom l) (lTo l) < 1] `shouldBe` []

    it "leaves clear space between discs on consecutive rings" $
      let ds = odDiscs drawing
          consecutive =
            [ dist (dCentre a) (dCentre b)
            | (a, b) <- pairs ds
            , abs (dRing a - dRing b) == 1
            ]
       in all (> 2 * cfgDiscRadius cfg) consecutive `shouldBe` True

    it "never draws a link through a disc" $
      [ ()
      | l <- odLinks drawing
      , d <- odDiscs drawing
      , passesThrough (cfgDiscRadius cfg) (dCentre d) l
      ]
        `shouldBe` []

    it "grows the radius with the ring" $
      let radiusPerRing =
            [ (dRing d, radiusOf d)
            | d <- odDiscs drawing
            ]
          ringOf k = [r | (k', r) <- radiusPerRing, k' == k]
       in and
            [ maximum (ringOf k) < minimum (ringOf (k + 1)) + 1e-6
            | k <- [0, 1]
            ]
            `shouldBe` True

    it "leaves the centre empty when there is more than one stream" $
      -- Three heads, so nothing sits at the eye.
      minimum (map radiusOf (odDiscs drawing)) `shouldSatisfy` (> 0)

    it "keeps a disc inside its own subtree's angular span" $
      -- What makes the drawing planar: a parent is the mean of its
      -- children's angles, so it can never wander into a sibling wedge.
      let f = unfold exampleNodes exampleEdges
          angleOf n r =
            head [dAngle d | d <- odDiscs drawing, dNode d == n, dReplica d == r]
          within t =
            let kids = otChildren t
             in null kids
                  || ( let ks = map (\k -> angleOf (otNode k) (otReplica k)) kids
                        in angleOf (otNode t) (otReplica t) >= minimum ks - 1e-9
                             && angleOf (otNode t) (otReplica t) <= maximum ks + 1e-9
                     )
                    && all within kids
       in all within f `shouldBe` True

    it "wraps each disc's label to the circle" $
      all (\d -> length (dLines d) <= cfgLabelLines cfg) (odDiscs drawing)
        `shouldBe` True

    it "bounds the drawing around every disc, with a margin" $
      let Bounds (Point x0 y0) (Point x1 y1) = odBounds drawing
          pad = cfgDiscRadius cfg + cfgMargin cfg
       in and
            [ x0 <= minimum (map (ptX . dCentre) (odDiscs drawing)) - pad + 1e-9
            , y0 <= minimum (map (ptY . dCentre) (odDiscs drawing)) - pad + 1e-9
            , x1 >= maximum (map (ptX . dCentre) (odDiscs drawing)) + pad - 1e-9
            , y1 >= maximum (map (ptY . dCentre) (odDiscs drawing)) + pad - 1e-9
            ]
            `shouldBe` True

    it "is deterministic" $
      orbit cfg exampleNodes exampleEdges `shouldBe` drawing

    it "does not depend on the order the rows arrive in" $
      orbit cfg (reverse exampleNodes) (reverse exampleEdges) `shouldBe` drawing

  describe "orbit, the single-head case" $ do
    it "puts a lone head at the centre" $
      -- A forest of one tree has no meaningful angular mean for its
      -- root -- its subtree spans the whole circle -- so it goes to the
      -- eye and the rings shift outward by one. Not a rare shape: a
      -- project whose work all converges on one deliverable.
      let d = orbit cfg (map node [1, 2, 3]) [dep 1 2, dep 1 3]
          headDisc = head [x | x <- odDiscs d, dRing x == 0]
       in radiusOf headDisc `shouldBe` 0

    it "still separates the discs around it" $
      let d = orbit cfg (map node [1, 2, 3]) [dep 1 2, dep 1 3]
          ds = odDiscs d
          minSep = 2 * cfgDiscRadius cfg
       in [() | (a, b) <- pairs ds, dist (dCentre a) (dCentre b) < minSep - 1e-6]
            `shouldBe` []

  describe "orbit, on input that should not exist" $ do
    it "draws an empty graph" $
      odDiscs (orbit cfg [] []) `shouldBe` []

    it "draws nodes with no edges at all, without overlapping them" $
      let d = orbit cfg (map node [1 .. 6]) []
          ds = odDiscs d
          minSep = 2 * cfgDiscRadius cfg
       in do
            length ds `shouldBe` 6
            [() | (a, b) <- pairs ds, dist (dCentre a) (dCentre b) < minSep - 1e-6]
              `shouldBe` []

    it "terminates on a cycle and still draws every node" $
      let d = orbit cfg (map node [1, 2]) [dep 1 2, dep 2 1]
       in sort (map dNode (odDiscs d)) `shouldSatisfy` (not . null)

    it "draws a node whose label is empty" $
      let d = orbit cfg [OrbitNode (NodeId 1) T.empty] []
       in map dLines (odDiscs d) `shouldBe` [[]]
