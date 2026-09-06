module Domain.Project.Graph.CoordSpec (spec) where

import qualified Data.Map.Strict as M
import Domain.Project.Graph.Coord (assignX)
import Domain.Project.Graph.Layer (Segment (..))
import Domain.Project.Graph.Types
  ( EdgeId (..)
  , EdgeKind (..)
  , LNode (..)
  , NodeId (..)
  , isDummy
  )
import Test.Hspec

{- | Uniform node width, so a "separation" in these tests is just
'width' + 'gap' and the arithmetic stays readable.
-}
width, gap, sep :: Double
width = 60
gap = 40
sep = width + gap

widthOf :: LNode -> Double
widthOf n = if isDummy n then 0 else width

nid :: Int -> LNode
nid = Real . NodeId . fromIntegral

-- | @arc a b@ puts @a@ in the row above @b@.
arc :: Int -> Int -> Int -> Segment
arc i a b = Segment (EdgeId (fromIntegral i)) DependsOn (nid a) (nid b) False

assign :: M.Map Int [LNode] -> [Segment] -> M.Map LNode Double
assign = assignX widthOf gap

xOf :: M.Map LNode Double -> Int -> Double
xOf xs n = M.findWithDefault (-1 / 0) (nid n) xs

-- | Every pair of adjacent centres in a row, in order.
gaps :: M.Map LNode Double -> [Int] -> [Double]
gaps xs row = zipWith (-) (drop 1 placed) placed
  where
    placed = map (xOf xs) row

-- | The horizontal extent a set of nodes occupies, box edge to box edge.
extentOf :: M.Map LNode Double -> [Int] -> (Double, Double)
extentOf xs ns =
  ( minimum [xOf xs n - width / 2 | n <- ns]
  , maximum [xOf xs n + width / 2 | n <- ns]
  )

-- | Do two extents share any horizontal space at all?
overlaps :: (Double, Double) -> (Double, Double) -> Bool
overlaps (a1, b1) (a2, b2) = a1 < b2 && a2 < b1

spec :: Spec
spec = do
  describe "assignX" $ do
    it "centres a parent between its two children" $ do
      let rows = M.fromList [(0, [nid 1]), (1, [nid 2, nid 3])]
          xs = assign rows [arc 10 1 2, arc 11 1 3]
      xOf xs 1 `shouldBe` (xOf xs 2 + xOf xs 3) / 2

    it "lines a single-child chain up vertically" $ do
      let rows = M.fromList [(0, [nid 1]), (1, [nid 2]), (2, [nid 3])]
          xs = assign rows [arc 10 1 2, arc 11 2 3]
      xOf xs 2 `shouldBe` xOf xs 1
      xOf xs 3 `shouldBe` xOf xs 1

    it "centres a parent over three children" $ do
      let rows = M.fromList [(0, [nid 1]), (1, [nid 2, nid 3, nid 4])]
          xs = assign rows [arc 10 1 2, arc 11 1 3, arc 12 1 4]
      xOf xs 1 `shouldBe` xOf xs 3

    it "keeps every node in a row at least one separation apart" $ do
      let rows = M.fromList [(0, [nid 1]), (1, [nid 2, nid 3, nid 4, nid 5])]
          xs = assign rows [arc 10 1 2, arc 11 1 3, arc 12 1 4, arc 13 1 5]
      all (>= sep) (gaps xs [2, 3, 4, 5]) `shouldBe` True

    it "never reorders a row within a component" $ do
      -- 4 wants to be far left (its only parent is), 2 far right, but
      -- placement may not swap them past each other.
      --
      -- Every node here hangs off 1 or 9 so the whole fixture is one
      -- component: packing regroups whole components, so a fixture made
      -- of several would be testing that instead of this.
      let rows = M.fromList [(0, [nid 1, nid 9]), (1, [nid 2, nid 3, nid 4])]
          xs =
            assign
              rows
              [arc 10 9 2, arc 11 1 4, arc 12 1 3, arc 13 9 3]
      all (> 0) (gaps xs [2, 3, 4]) `shouldBe` True

    it "keeps rows separated when a wide row sits under a narrow one" $ do
      let rows = M.fromList [(0, [nid 1, nid 2]), (1, [nid 3, nid 4, nid 5])]
          xs = assign rows [arc 10 1 3, arc 11 1 4, arc 12 2 5]
      all (>= sep) (gaps xs [3, 4, 5]) `shouldBe` True
      all (>= sep) (gaps xs [1, 2]) `shouldBe` True

    it "places nodes with no edges without crashing" $ do
      let rows = M.fromList [(0, [nid 1, nid 2])]
          xs = assign rows []
      M.size xs `shouldBe` 2
      all (>= sep) (gaps xs [1, 2]) `shouldBe` True

    it "is deterministic" $ do
      let rows = M.fromList [(0, [nid 1]), (1, [nid 2, nid 3]), (2, [nid 4])]
          as = [arc 10 1 2, arc 11 1 3, arc 12 2 4, arc 13 3 4]
      assign rows as `shouldBe` assign rows as

    it "handles an empty graph" $
      assign M.empty [] `shouldBe` M.empty

  describe "assignX, component packing" $ do
    {- Component A is one node wide at the top
    and four wide two rows down, so without packing its lower row
    spreads out underneath B and B ends up sitting inside A's span
    rather than beside it. -}
    let packRows =
          M.fromList
            [ (0, [nid 1, nid 2])
            , (1, [nid 3, nid 4])
            , (2, [nid 5, nid 6, nid 7, nid 8])
            ]
        packArcs =
          [ arc 10 1 3
          , arc 11 3 5
          , arc 12 3 6
          , arc 13 3 7
          , arc 14 3 8
          , arc 15 2 4
          ]
        compA = [1, 3, 5, 6, 7, 8]
        compB = [2, 4]

    it "keeps one component from sitting inside another's span" $ do
      let xs = assign packRows packArcs
      overlaps (extentOf xs compA) (extentOf xs compB) `shouldBe` False

    it "keeps every row's separation after packing" $ do
      let xs = assign packRows packArcs
      all (>= sep) (gaps xs [5, 6, 7, 8]) `shouldBe` True

    it "moves a component rigidly, preserving its internal shape" $ do
      let xs = assign packRows packArcs
          -- B is a vertical chain, so packing must leave it vertical.
          before = xOf xs 2 - xOf xs 4
      before `shouldBe` 0

    it "leaves a single connected component untouched" $ do
      -- One component, so packing has nothing to separate and the
      -- priority method's output must survive unchanged.
      let rows = M.fromList [(0, [nid 1]), (1, [nid 2, nid 3])]
          as = [arc 10 1 2, arc 11 1 3]
          xs = assign rows as
      xOf xs 1 `shouldBe` (xOf xs 2 + xOf xs 3) / 2

    it "leaves components that were already clear of each other alone" $ do
      -- Two side-by-side chains: nothing overlaps, so nothing should
      -- move. Packing only ever pushes right to fix an overlap.
      let rows = M.fromList [(0, [nid 1, nid 2]), (1, [nid 3, nid 4])]
          as = [arc 10 1 3, arc 11 2 4]
          xs = assign rows as
      gaps xs [1, 2] `shouldBe` [sep]
      gaps xs [3, 4] `shouldBe` [sep]

    it "is deterministic" $ do
      assign packRows packArcs `shouldBe` assign packRows packArcs
