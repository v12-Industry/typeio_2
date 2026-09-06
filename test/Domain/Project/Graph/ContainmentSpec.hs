module Domain.Project.Graph.ContainmentSpec (spec) where

import Data.List (sort)
import qualified Data.Text as T
import Domain.Project.Graph.Containment (containmentEdges, containmentTargets)
import Domain.Project.Graph.Types
  ( EdgeId (..)
  , EdgeKind (..)
  , LayoutEdge (..)
  , LayoutNode (..)
  , NodeId (..)
  , NodeKind (..)
  , dependsOn
  )
import Test.Hspec

-- | @node n@ is a work node whose id and label are both derived from n.
node :: Int -> LayoutNode
node n = LayoutNode (NodeId (fromIntegral n)) WorkNode (T.pack ("node " <> show n))

-- | The project root, always id 0 here.
root :: LayoutNode
root = LayoutNode (NodeId 0) RootNode (T.pack "root")

{- | @dep i a b@: node @b@ depends on node @a@, so @a@ must finish first
and @b@ is drawn above it.
-}
dep :: Int -> Int -> Int -> LayoutEdge
dep i a b =
  dependsOn
    (EdgeId (fromIntegral i))
    (NodeId (fromIntegral a))
    (NodeId (fromIntegral b))

-- | Which work the root ends up attached to, as plain ints.
targets :: [LayoutNode] -> [LayoutEdge] -> [Int]
targets lns les =
  [fromIntegral n | NodeId n <- containmentTargets root lns les]

spec :: Spec
spec = do
  describe "containmentTargets" $ do
    it "attaches the root to a lone work node" $ do
      -- Nothing depends on it, so it is its own head. Without this it
      -- would float away from the project entirely.
      targets [root, node 1] [] `shouldBe` [1]

    it "attaches the root to every unconnected node" $ do
      targets [root, node 1, node 2, node 3] [] `shouldBe` [1, 2, 3]

    it "attaches the root to a chain's head only" $ do
      -- 3 depends on 2 depends on 1, so 3 is the top of the chain and
      -- 1 and 2 reach the root through it. A root edge on each would
      -- bury the chain under three redundant edges.
      targets [root, node 1, node 2, node 3] [dep 10 1 2, dep 11 2 3]
        `shouldBe` [3]

    it "attaches the root to one head per independent chain" $ do
      targets
        [root, node 1, node 2, node 3, node 4]
        [dep 10 1 2, dep 11 3 4]
        `shouldBe` [2, 4]

    it "attaches the root once to a node several things depend on" $ do
      -- A diamond: 4 depends on 2 and 3, both of which depend on 1.
      -- Only 4 has nothing above it.
      targets
        [root, node 1, node 2, node 3, node 4]
        [dep 10 1 2, dep 11 1 3, dep 12 2 4, dep 13 3 4]
        `shouldBe` [4]

    it "attaches the root to a head that also has its own dependencies" $ do
      -- The head of a chain is still attached even though it depends on
      -- other work -- "attached to the root or to work, not both" is
      -- about what sits *above* a node, and nothing sits above a head.
      targets [root, node 1, node 2] [dep 10 1 2] `shouldBe` [2]

    it "anchors a pure cycle, which has no head at all" $ do
      -- Every node in a cycle is something's dependency, so rule 1
      -- finds nothing. Without rule 2 the whole group would drift off
      -- as an island unattached to the project.
      targets [root, node 1, node 2] [dep 10 1 2, dep 11 2 1]
        `shouldBe` [1]

    it "anchors a self-dependency" $ do
      targets [root, node 1] [dep 10 1 1] `shouldBe` [1]

    it "anchors a cycle once, not once per node" $ do
      targets
        [root, node 1, node 2, node 3]
        [dep 10 1 2, dep 11 2 3, dep 12 3 1]
        `shouldBe` [1]

    it "anchors a cycle and still takes the heads elsewhere" $ do
      -- A cycle between 1 and 2, and a separate chain 3 <- 4.
      targets
        [root, node 1, node 2, node 3, node 4]
        [dep 10 1 2, dep 11 2 1, dep 12 3 4]
        `shouldBe` [4, 1]

    it "does not attach the root to a tail hanging off a cycle" $ do
      -- 3 depends on the cycle, so it is reachable from the anchor and
      -- needs no root edge of its own.
      targets
        [root, node 1, node 2, node 3]
        [dep 10 1 2, dep 11 2 1, dep 12 1 3]
        `shouldBe` [3]

    it "leaves a node the root already sits above alone" $ do
      -- A stored row recording "the root is waiting on node 1" is the
      -- pre-migration-000009 way of writing membership. The schema
      -- still permits one, and it already puts the root above that
      -- node -- deriving a second edge would draw the same
      -- relationship twice, side by side.
      targets [root, node 1] [dep 10 1 0] `shouldBe` []

    it "still takes the heads that such a row does not cover" $ do
      targets [root, node 1, node 2] [dep 10 1 0] `shouldBe` [2]

    it "returns nothing for a project with no work" $ do
      targets [root] [] `shouldBe` []

    it "is deterministic" $ do
      let lns = [root, node 3, node 1, node 2]
          les = [dep 10 1 2, dep 11 2 1]
      targets lns les `shouldBe` targets lns les

  describe "containmentEdges" $ do
    it "emits nothing when the project has no root" $ do
      containmentEdges [node 1, node 2] [] `shouldBe` []

    it "draws the root above the work it holds" $ do
      -- The root is the upper end: that is what puts it at the head of
      -- the drawing. Reversed, layering works correctly and sinks the
      -- root to the bottom, which is not visibly a bug in the layout.
      let es = containmentEdges [root, node 1] []
      map (\e -> (leUpper e, leLower e)) es `shouldBe` [(NodeId 0, NodeId 1)]

    it "marks its edges as containment, not dependencies" $ do
      let es = containmentEdges [root, node 1] []
      map leKind es `shouldBe` [Contains]

    it "gives every derived edge a distinct negative id" $ do
      -- Negative so they cannot collide with a real project.dependency
      -- id, distinct so nothing downstream conflates two of them.
      let es = containmentEdges [root, node 1, node 2, node 3] []
          ids = [i | EdgeId i <- map leId es]
      all (< 0) ids `shouldBe` True
      length ids `shouldBe` 3
      sort ids `shouldBe` [-3, -2, -1]

    it "emits one edge per head, not one per node" $ do
      -- Stated as a reader would notice it: five work nodes in a
      -- chain, one root edge.
      let lns = root : map node [1 .. 5]
          les = [dep 10 1 2, dep 11 2 3, dep 12 3 4, dep 13 4 5]
      length (containmentEdges lns les) `shouldBe` 1
