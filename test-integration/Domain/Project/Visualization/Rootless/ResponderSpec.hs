{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for the rootless visualization.

Like @ProjectManage.GraphSpec@, these assertions are about the rendered
markup rather than geometry: the layout engine is shared with the
layered visualization and is unit-tested there, so what needs pinning
here is the /conversion/ — which nodes and edges this visualization
decides the drawing is of.

Three things, and each one is a way the visualization could regress into
looking like the layered one:

1.  No project root is drawn.
2.  No containment edge is derived.
3.  A stored dependency that referred to the root goes with it, rather
    than surviving into layout pointing at a node that is no longer
    there.
-}
module Domain.Project.Visualization.Rootless.ResponderSpec (spec) where

import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.Int (Int64)
import Data.List (isInfixOf, isPrefixOf, tails)
import Database.Persist.Sql (ConnectionPool, fromSqlKey)
import Domain.Project.Visualization.Rootless.Responder (handleProjectGraph)
import Integration.Support
  ( resetBetweenTests
  , seedDependency
  , seedProjectWithRootNode
  , seedWorkNode
  , withTestDatabase
  )
import Network.HTTP.Types (methodGet)
import Network.Wai (Request, defaultRequest, queryString, requestMethod)
import Network.Wai.Test
  ( SResponse (..)
  , assertStatus
  , request
  , runSession
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestDatabase $
  beforeWith resetBetweenTests $
    describe "handleProjectGraph, rootless (integration)" $ do
      it "draws no project root" $ \pool -> do
        (projectKey, _) <- seedProjectWithRootNode pool
        _ <- seedWorkNode pool projectKey "Build the thing"

        body <- graphBody pool (fromSqlKey projectKey)

        -- The layered visualization renders the root as
        -- `<rect class="root"`; the whole point here is that it isn't
        -- in the document at all.
        body `shouldNotContainStr` "<rect class=\"root\""
        body `shouldContainStr` "<rect class=\"work\""

      it "derives no containment edge" $ \pool -> do
        (projectKey, _) <- seedProjectWithRootNode pool
        _ <- seedWorkNode pool projectKey "Build the thing"

        body <- graphBody pool (fromSqlKey projectKey)

        -- `link-contains` is the class the derived root-to-work edges
        -- carry. With no root there is nothing to derive them from.
        body `shouldNotContainStr` "link-contains"

      it "drops a stored dependency that pointed at the root" $ \pool -> do
        -- The pre-migration-000009 way of recording membership, and
        -- still possible for a hand-written row. Keeping such an edge
        -- after removing the root would leave layout an edge referring
        -- to a node that is not in the drawing: `layout` is total and
        -- would place the missing end at the origin, drawing a stray
        -- arrow into empty space rather than failing.
        (projectKey, rootKey) <- seedProjectWithRootNode pool
        workKey <- seedWorkNode pool projectKey "Build the thing"
        seedDependency pool rootKey workKey

        body <- graphBody pool (fromSqlKey projectKey)

        -- One work node, and therefore no edges at all: the only
        -- relationship in this project involved the root.
        countStr "<rect class=\"work\"" body `shouldBe` 1
        countStr "class=\"link" body `shouldBe` 0

      it "still draws a dependency between two work nodes" $ \pool -> do
        -- The negative tests above would all pass on a visualization
        -- that drew nothing whatsoever, so pin the positive case too.
        (projectKey, _) <- seedProjectWithRootNode pool
        a <- seedWorkNode pool projectKey "First"
        b <- seedWorkNode pool projectKey "Second"
        seedDependency pool a b

        body <- graphBody pool (fromSqlKey projectKey)

        countStr "<rect class=\"work\"" body `shouldBe` 2
        body `shouldContainStr` "class=\"link\""
        body `shouldContainStr` "marker-end=\"url(#arrow)\""

      it "serves the same viewport script as the layered drawing" $ \pool -> do
        -- Shared rendering, so the pan/zoom layer has to arrive with
        -- this fragment too -- it is loaded from inside the fragment
        -- rather than at page load.
        (projectKey, _) <- seedProjectWithRootNode pool
        _ <- seedWorkNode pool projectKey "Build the thing"

        body <- graphBody pool (fromSqlKey projectKey)

        body `shouldContainStr` "/static/script/graph-viewport.js"
        body `shouldContainStr` "id=\"graph-zoom-layer\""

-- | GET the graph view and hand its body back as a searchable 'String'.
graphBody :: ConnectionPool -> Int64 -> IO String
graphBody pool pid =
  runSession
    ( do
        resp <- request (graphRequest pid)
        assertStatus 200 resp
        pure . LC8.unpack . simpleBody $ resp
    )
    (handleProjectGraph pool)

graphRequest :: Int64 -> Request
graphRequest pid =
  defaultRequest
    { requestMethod = methodGet
    , queryString = [("projectId", Just . C8.pack . show $ pid)]
    }

countStr :: String -> String -> Int
countStr needle = length . filter (needle `isPrefixOf`) . tails

shouldContainStr :: String -> String -> Expectation
shouldContainStr haystack needle =
  (needle `isInfixOf` haystack)
    `shouldSatisfyWith` ("expected the rendered graph to contain " <> show needle)

shouldNotContainStr :: String -> String -> Expectation
shouldNotContainStr haystack needle =
  not (needle `isInfixOf` haystack)
    `shouldSatisfyWith` ("expected the rendered graph not to contain " <> show needle)

shouldSatisfyWith :: Bool -> String -> Expectation
shouldSatisfyWith True _ = pure ()
shouldSatisfyWith False msg = expectationFailure msg
