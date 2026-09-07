module Domain.Project.Orbit.UnfoldSpec (spec) where

import Data.List (sort)
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import Domain.Project.Orbit.Types
  ( NodeId (..)
  , OrbitEdge (..)
  , OrbitNode (..)
  , OrbitTree (..)
  )
import Domain.Project.Orbit.Unfold (discs, heads, unfold)
import Test.Hspec

-- | @node n@ is a work node whose id and label are both derived from n.
node :: Int -> OrbitNode
node n = OrbitNode (NodeId (fromIntegral n)) (T.pack ("node " <> show n))

{- | @dep a b@: node @a@ depends on node @b@, so @b@ must finish first.
@a@ is drawn nearer the eye and carries the arrowhead.
-}
dep :: Int -> Int -> OrbitEdge
dep a b = OrbitEdge (NodeId (fromIntegral a)) (NodeId (fromIntegral b))

nid :: Int -> NodeId
nid = NodeId . fromIntegral

{- | The worked example from
@docs/architecture/orbital-dependency-weighted-graph.md@.

Nodes 1-7 stand for A-G:

> A=1  B=2  C=3  D=4  E=5  F=6  G=7

with A depending on D, D on E, B on C, C on E, and F on both G and C.
Heads are A, B and F; E is reached by three different streams and C by
two.
-}
exampleNodes :: [OrbitNode]
exampleNodes = map node [1 .. 7]

exampleEdges :: [OrbitEdge]
exampleEdges =
  [ dep 1 4 -- A depends on D
  , dep 4 5 -- D depends on E
  , dep 2 3 -- B depends on C
  , dep 3 5 -- C depends on E
  , dep 6 7 -- F depends on G
  , dep 6 3 -- F depends on C
  ]

-- | Every disc's node id, parents before children.
drawnNodes :: [OrbitTree] -> [NodeId]
drawnNodes = map otNode . discs

-- | How many discs each node got.
timesDrawn :: [OrbitTree] -> M.Map NodeId Int
timesDrawn f = M.fromListWith (+) [(n, 1 :: Int) | n <- drawnNodes f]

-- | The node ids on each ring.
ring :: Int -> [OrbitTree] -> [NodeId]
ring k f = sort [otNode t | t <- discs f, otRing t == k]

spec :: Spec
spec = do
  describe "heads" $ do
    it "takes the nodes nothing is waiting on" $
      heads exampleNodes exampleEdges `shouldBe` map nid [1, 2, 6]

    it "counts a node with no dependencies at all as its own head" $
      heads [node 1] [] `shouldBe` [nid 1]

    it "ignores an edge naming a node that was not supplied" $
      -- 99 is not in the node list, so it cannot make 1 a non-head.
      heads [node 1] [dep 99 1] `shouldBe` [nid 1]

    it "finds no head in a pure cycle, since every node is waited on" $
      heads (map node [1, 2]) [dep 1 2, dep 2 1] `shouldBe` []

  describe "unfold" $ do
    it "draws the worked example as ten discs for seven nodes" $
      length (discs (unfold exampleNodes exampleEdges)) `shouldBe` 10

    it "replicates a node once per stream that reaches it" $ do
      let counts = timesDrawn (unfold exampleNodes exampleEdges)
      -- E is waited on by D and by both copies of C; C by B and F.
      M.lookup (nid 5) counts `shouldBe` Just 3
      M.lookup (nid 3) counts `shouldBe` Just 2

    it "draws every other node exactly once" $ do
      let counts = timesDrawn (unfold exampleNodes exampleEdges)
      map (`M.lookup` counts) (map nid [1, 2, 4, 6, 7])
        `shouldBe` replicate 5 (Just 1)

    it "puts one tree on each head" $
      map otNode (unfold exampleNodes exampleEdges) `shouldBe` map nid [1, 2, 6]

    it "rings the discs by depth from their head" $ do
      let f = unfold exampleNodes exampleEdges
      ring 0 f `shouldBe` map nid [1, 2, 6]
      ring 1 f `shouldBe` map nid [3, 3, 4, 7]
      ring 2 f `shouldBe` map nid [5, 5, 5]

    it "gives every disc but a head exactly one dependent" $ do
      -- In the drawing each disc hangs off exactly one parent, which is
      -- what the whole no-crossings claim rests on. A tree has that by
      -- construction, so what is worth asserting is that the forest is
      -- made only of trees: as many parent slots as non-root discs.
      let f = unfold exampleNodes exampleEdges
          children = sum (map (length . otChildren) (discs f))
      children `shouldBe` length (discs f) - length f

    it "replicates a whole subtree, not just the shared node" $ do
      -- C is replicated, so the E beneath it is replicated with it.
      let f = unfold exampleNodes exampleEdges
          cs = [t | t <- discs f, otNode t == nid 3]
      map (map otNode . otChildren) cs `shouldBe` [[nid 5], [nid 5]]

    it "does not replicate a node that merely has several dependencies" $ do
      -- F waits on both G and C and is still drawn once: replication is
      -- driven by dependents, not dependencies.
      let counts = timesDrawn (unfold exampleNodes exampleEdges)
      M.lookup (nid 6) counts `shouldBe` Just 1

    it "numbers a node's replicas 0, 1, 2 across the whole forest" $ do
      let f = unfold exampleNodes exampleEdges
          es = [otReplica t | t <- discs f, otNode t == nid 5]
      sort es `shouldBe` [0, 1, 2]

    it "gives every disc of a once-drawn node replica 0" $ do
      let f = unfold exampleNodes exampleEdges
          singles = [otReplica t | t <- discs f, otNode t `elem` map nid [1, 2, 4, 6, 7]]
      singles `shouldBe` replicate 5 0

    it "draws every node at least once" $
      sort (map onId exampleNodes)
        `shouldBe` sort (foldr dedupe [] (sort (drawnNodes (unfold exampleNodes exampleEdges))))

    it "is deterministic" $
      unfold exampleNodes exampleEdges `shouldBe` unfold exampleNodes exampleEdges

    it "does not depend on the order the rows arrive in" $
      unfold (reverse exampleNodes) (reverse exampleEdges)
        `shouldBe` unfold exampleNodes exampleEdges

  describe "unfold, on input that should not exist" $ do
    it "terminates on a cycle" $ do
      -- Cycles are rejected upstream; this is the backstop that stops
      -- one hanging the request if it arrives by seed script or direct
      -- SQL.
      let f = unfold (map node [1, 2]) [dep 1 2, dep 2 1]
      length (discs f) `shouldSatisfy` (> 0)

    it "still draws a wholly cyclic group, rather than dropping it" $ do
      let f = unfold (map node [1, 2]) [dep 1 2, dep 2 1]
      sort (foldr dedupe [] (sort (drawnNodes f))) `shouldBe` map nid [1, 2]

    it "terminates on a self-dependency" $
      length (discs (unfold [node 1] [dep 1 1])) `shouldBe` 1

    it "draws the work hanging off a cycle" $ do
      -- 3 depends on 1, and 1/2 are a cycle. Nothing waits on 3, so 3
      -- is the head and the cycle is reached through it.
      let f = unfold (map node [1, 2, 3]) [dep 1 2, dep 2 1, dep 3 1]
      map otNode f `shouldBe` [nid 3]
      sort (foldr dedupe [] (sort (drawnNodes f))) `shouldBe` map nid [1, 2, 3]

    it "handles an empty graph" $
      unfold [] [] `shouldBe` []

    it "handles nodes with no edges at all" $ do
      let f = unfold (map node [1, 2, 3]) []
      map otNode f `shouldBe` map nid [1, 2, 3]
      map otChildren f `shouldBe` [[], [], []]

    it "ignores a duplicate edge rather than drawing it twice" $ do
      -- UNIQUE (node_id, to_node_id) makes this unreachable from the
      -- database, but 'unfold' is total and must not double the drawing
      -- if one arrives another way.
      let f = unfold (map node [1, 2]) [dep 1 2, dep 1 2]
      length (discs f) `shouldBe` 2

dedupe :: NodeId -> [NodeId] -> [NodeId]
dedupe x (y : ys) | x == y = y : ys
dedupe x ys = x : ys
