{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for the rootless visualization.

These assertions are about the rendered markup rather than geometry:
the layout engine this visualization draws with is shared, and is
unit-tested under @test\/Domain\/Project\/Graph\/@, so what needs
pinning here is the /conversion/ — which nodes and edges this
visualization decides the drawing is of.

Three things, and each one is a way the drawing could quietly grow a
root it is not supposed to have:

1.  No project root is drawn.
2.  No containment edge is derived.
3.  A stored dependency that referred to the root goes with it, rather
    than surviving into layout pointing at a node that is no longer
    there.
-}
module Domain.Project.Visualization.Rootless.ResponderSpec (spec) where

import Data.Int (Int64)
import Data.Text (Text, pack)
import Database.Persist.Sql (fromSqlKey)
import Integration.Support
  ( TestApp
  , bodyOf
  , countStr
  , httpGet
  , resetBetweenTests
  , seedDependency
  , seedProjectWithRootNode
  , seedWorkNode
  , shouldContainStr
  , shouldNotContainStr
  , statusOf
  , withTestApp
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestApp $
  beforeWith resetBetweenTests $
    describe "GET /ui/project/graph?visualizationMode=Rootless (integration)" $ do
      it "draws no project root" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta
        _ <- seedWorkNode ta projectKey "Build the thing"

        body <- graphBody ta (fromSqlKey projectKey)

        -- A drawn root would arrive as `<rect class="root`; the whole
        -- point here is that it isn't in the document at all. The class
        -- is matched without its closing quote because the node's
        -- status rides in the same attribute.
        body `shouldNotContainStr` "<rect class=\"root"
        body `shouldContainStr` "<rect class=\"work"

      it "derives no containment edge" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta
        _ <- seedWorkNode ta projectKey "Build the thing"

        body <- graphBody ta (fromSqlKey projectKey)

        -- `link-contains` is the class the derived root-to-work edges
        -- carry. With no root there is nothing to derive them from.
        body `shouldNotContainStr` "link-contains"

      it "drops a stored dependency that pointed at the root" $ \ta -> do
        -- The pre-migration-000009 way of recording membership, and
        -- still possible for a hand-written row. Keeping such an edge
        -- after removing the root would leave layout an edge referring
        -- to a node that is not in the drawing: `layout` is total and
        -- would place the missing end at the origin, drawing a stray
        -- arrow into empty space rather than failing.
        (projectKey, rootKey) <- seedProjectWithRootNode ta
        workKey <- seedWorkNode ta projectKey "Build the thing"
        seedDependency ta rootKey workKey

        body <- graphBody ta (fromSqlKey projectKey)

        -- One work node, and therefore no edges at all: the only
        -- relationship in this project involved the root.
        countStr "<rect class=\"work" body `shouldBe` 1
        countStr "class=\"link" body `shouldBe` 0

      it "still draws a dependency between two work nodes" $ \ta -> do
        -- The negative tests above would all pass on a visualization
        -- that drew nothing whatsoever, so pin the positive case too.
        (projectKey, _) <- seedProjectWithRootNode ta
        a <- seedWorkNode ta projectKey "First"
        b <- seedWorkNode ta projectKey "Second"
        seedDependency ta a b

        body <- graphBody ta (fromSqlKey projectKey)

        countStr "<rect class=\"work" body `shouldBe` 2
        body `shouldContainStr` "class=\"link\""
        body `shouldContainStr` "marker-end=\"url(#arrow)\""

      it "carries each node's status as a class on its shape" $ \ta -> do
        -- Status is drawn as colour, and the colour is CSS's decision:
        -- what the server owes the stylesheet is the class, and nothing
        -- else. A fill or a hue emitted here would be the appearance
        -- leaking back into the markup.
        (projectKey, _) <- seedProjectWithRootNode ta
        _ <- seedWorkNode ta projectKey "Build the thing"

        body <- graphBody ta (fromSqlKey projectKey)

        -- seedWorkNode stores "active", the status every node is
        -- created with.
        body `shouldContainStr` "<rect class=\"work status-active\""

      it "serves the shared viewport script with the drawing" $ \ta -> do
        -- Shared rendering, so the pan/zoom layer has to arrive with
        -- this fragment too -- it is loaded from inside the fragment
        -- rather than at page load.
        (projectKey, _) <- seedProjectWithRootNode ta
        _ <- seedWorkNode ta projectKey "Build the thing"

        body <- graphBody ta (fromSqlKey projectKey)

        body `shouldContainStr` "/static/script/graph-viewport.js"
        body `shouldContainStr` "id=\"graph-zoom-layer\""

-- | GET the graph fragment and hand its body back as a searchable 'String'.
graphBody :: TestApp -> Int64 -> IO String
graphBody ta pid = do
  resp <- httpGet ta (graphUrl pid)
  statusOf resp `shouldBe` 200
  pure (bodyOf resp)

graphUrl :: Int64 -> Text
graphUrl pid =
  "/ui/project/graph?projectId=" <> pack (show pid) <> "&visualizationMode=Rootless"
