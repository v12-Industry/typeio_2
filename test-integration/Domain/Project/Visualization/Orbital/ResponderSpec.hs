{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for the orbital visualization's renderer
(#237).

Like @Rootless.ResponderSpec@, these assertions are about the rendered
markup rather than geometry: the placement is pure and unit-tested in
@Orbit.LayoutSpec@, so what needs pinning here is what only shows up in
a finished document — the conversion, the DOM contract, and the wiring
that makes the drawing part of the Project Manage UI rather than a
picture sitting next to it.

The replica assertions are the ones with no counterpart in any other
visualization, and they are the reason this file exists: a node with
two dependents must come out as __two circles sharing one
@data-node-id@ and carrying different ids__. Get either half wrong and
the drawing still renders — it just quietly stops being usable, because
the panel highlight and the label refresh both find one arbitrary copy.
-}
module Domain.Project.Visualization.Orbital.ResponderSpec (spec) where

import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.Int (Int64)
import Data.List (isInfixOf, isPrefixOf, nub, tails)
import Database.Persist.Sql (ConnectionPool, Key, fromSqlKey)
import qualified Domain.Project.Model as M
import Domain.Project.Visualization.Orbital.Responder (handleProjectGraph)
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
    describe "handleProjectGraph, orbital (integration)" $ do
      it "draws the work as circles, and no project root" $ \pool -> do
        (projectKey, _) <- seedProjectWithRootNode pool
        _ <- seedWorkNode pool projectKey "Build the thing"

        body <- graphBody pool (fromSqlKey projectKey)

        body `shouldContainStr` "<circle class=\"work\""
        -- Rootless-like: the project node is not in the picture. There
        -- is no `root` shape of any kind to find.
        body `shouldNotContainStr` "class=\"root\""

      it "drops a stored dependency that pointed at the root" $ \pool -> do
        -- The pre-migration-000009 way of recording membership. Kept,
        -- it would name a node that is not in the drawing -- `orbit` is
        -- total and would draw a link into empty space rather than
        -- failing.
        (projectKey, rootKey) <- seedProjectWithRootNode pool
        workKey <- seedWorkNode pool projectKey "Build the thing"
        seedDependency pool rootKey workKey

        body <- graphBody pool (fromSqlKey projectKey)

        countStr "<circle class=\"work\"" body `shouldBe` 1
        countStr "class=\"link\"" body `shouldBe` 0

      it "still draws a dependency between two work nodes" $ \pool -> do
        -- Every negative assertion here would also pass on a
        -- visualization that drew nothing at all, so pin the positive
        -- case.
        (projectKey, _) <- seedProjectWithRootNode pool
        a <- seedWorkNode pool projectKey "First"
        b <- seedWorkNode pool projectKey "Second"
        seedDependency pool a b

        body <- graphBody pool (fromSqlKey projectKey)

        countStr "<circle class=\"work\"" body `shouldBe` 2
        body `shouldContainStr` "class=\"link\""
        body `shouldContainStr` "marker-end=\"url(#arrow)\""

      describe "replication" $ do
        it "draws a node once per dependent" $ \pool -> do
          -- Two nodes waiting on one. The shared node cannot belong to
          -- both streams, so it is drawn in each -- three nodes, four
          -- circles. This is the whole premise of the visualization.
          (projectKey, shared) <- sharedDependencyFixture pool

          body <- graphBody pool (fromSqlKey projectKey)

          countStr "<circle class=\"work\"" body `shouldBe` 4
          countStr (dataNodeId shared) body `shouldBe` 2

        it "gives each replica its own id" $ \pool -> do
          (projectKey, shared) <- sharedDependencyFixture pool

          body <- graphBody pool (fromSqlKey projectKey)

          body `shouldContainStr` discId shared 0
          body `shouldContainStr` discId shared 1

        it "asks the refresh endpoint for the circle's wrap width" $ \pool -> do
          -- A circle fits fewer characters per line than the layered
          -- drawing's box, and both share one refresh endpoint, so each
          -- disc has to say which width it wants. Without it an edited
          -- label comes back wrapped to the other shape.
          (projectKey, _) <- sharedDependencyFixture pool

          body <- graphBody pool (fromSqlKey projectKey)

          countStr "wrapWidth=12" body `shouldBe` 4
          body `shouldNotContainStr` "wrapWidth=18"

        it "gives each replica its own label id" $ \pool -> do
          -- Unique per circle, which is what the per-node label
          -- refresh needs once it arrives (#244).
          (projectKey, shared) <- sharedDependencyFixture pool

          body <- graphBody pool (fromSqlKey projectKey)

          body `shouldContainStr` discTextId shared 0
          body `shouldContainStr` discTextId shared 1

        it "opens the same node's panel from either replica" $ \pool -> do
          -- Clicking any copy opens the same panel and pushes the same
          -- URL: they are the same node.
          (projectKey, shared) <- sharedDependencyFixture pool

          body <- graphBody pool (fromSqlKey projectKey)

          countStr (panelLink shared (fromSqlKey projectKey)) body
            `shouldBe` 2

      describe "replica identity (#239)" $ do
        it "gives every replica of a node the same colour" $ \pool -> do
          -- Colour is what tells a reader that two circles are one
          -- node, so a replica in a different hue is not a cosmetic
          -- bug -- it is a false statement about the project.
          (projectKey, shared) <- sharedDependencyFixture pool

          body <- graphBody pool (fromSqlKey projectKey)

          let hues = huesFor (show (fromSqlKey shared)) body
          length hues `shouldBe` 2
          length (nub hues) `shouldBe` 1

        it "gives different nodes different colours" $ \pool -> do
          -- The whole palette would satisfy the test above.
          (projectKey, _) <- sharedDependencyFixture pool

          body <- graphBody pool (fromSqlKey projectKey)

          let byNode = nub (discHues body)
              distinctHues = nub (map snd byNode)
          length distinctHues `shouldBe` length byNode

        it "highlights every replica from a hover on any of them" $ \pool -> do
          -- Selects on data-node-id, so one line covers one disc or
          -- five. `.replica-hover` rather than `.node-highlight`: the
          -- node panel owns that class on the same elements, and a
          -- mouseleave must not strip a highlight it put there.
          (projectKey, shared) <- sharedDependencyFixture pool

          body <- graphBody pool (fromSqlKey projectKey)

          body
            `shouldContainStr` ( "add .replica-hover to &lt;[data-node-id=&#39;"
                                   <> show (fromSqlKey shared)
                                   <> "&#39;]/&gt;"
                               )
          body `shouldContainStr` "remove .replica-hover from"

      describe "the DOM contract" $ do
        it "tags every disc with the node it stands for" $ \pool -> do
          -- The one thing this visualization owes the Project Manage
          -- UI (#234): the panel highlight and the post-edit flash
          -- both select on this.
          (projectKey, _) <- seedProjectWithRootNode pool
          workKey <- seedWorkNode pool projectKey "Build the thing"

          body <- graphBody pool (fromSqlKey projectKey)

          body `shouldContainStr` dataNodeId workKey

        it "wires every disc to the node panel" $ \pool -> do
          (projectKey, _) <- seedProjectWithRootNode pool
          _ <- seedWorkNode pool projectKey "Build the thing"

          body <- graphBody pool (fromSqlKey projectKey)

          body `shouldContainStr` "hx-target=\"#node-panel\""
          body `shouldContainStr` "hx-trigger=\"click\""

        it "uses its own id prefix rather than the layered one" $ \pool -> do
          -- Deliberately a different prefix, not a longer `#node-` id.
          -- Several circles share a node here, so anything still
          -- querying `#node-<id>` should find nothing rather than
          -- silently match one arbitrary replica.
          (projectKey, _) <- sharedDependencyFixture pool

          body <- graphBody pool (fromSqlKey projectKey)

          body `shouldNotContainStr` "id=\"node-"
          body `shouldNotContainStr` "id=\"node-text-"

        it "ships the zoom layer and the viewport script" $ \pool -> do
          -- Comes from the shared frame (#242) rather than from
          -- anything written here, which is the point of that issue.
          (projectKey, _) <- seedProjectWithRootNode pool
          _ <- seedWorkNode pool projectKey "Build the thing"

          body <- graphBody pool (fromSqlKey projectKey)

          body `shouldContainStr` "id=\"graph-zoom-layer\""
          body `shouldContainStr` "/static/script/graph-viewport.js"

        it "emits no root anchor, so the viewport opens on the eye" $ \pool -> do
          -- There is no root to open on, and the frame's fallback --
          -- the centre of the drawing -- is exactly the eye.
          (projectKey, _) <- sharedDependencyFixture pool

          body <- graphBody pool (fromSqlKey projectKey)

          body `shouldNotContainStr` "data-root-x"
          body `shouldContainStr` "data-base-width"

{- | Two work nodes waiting on a third, plus the project root. Returns
the project and the shared node -- the one that gets replicated.
-}
sharedDependencyFixture :: ConnectionPool -> IO (Key M.Project, Key M.Node)
sharedDependencyFixture pool = do
  (projectKey, _) <- seedProjectWithRootNode pool
  shared <- seedWorkNode pool projectKey "Finish the auth service"
  a <- seedWorkNode pool projectKey "Publish the launch post"
  b <- seedWorkNode pool projectKey "Ship the mobile client"
  seedDependency pool a shared
  seedDependency pool b shared
  pure (projectKey, shared)

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

dataNodeId :: Key M.Node -> String
dataNodeId k = "data-node-id=\"" <> show (fromSqlKey k) <> "\""

discId :: Key M.Node -> Int -> String
discId k n = "id=\"disc-" <> show (fromSqlKey k) <> "-" <> show n <> "\""

discTextId :: Key M.Node -> Int -> String
discTextId k n =
  "id=\"disc-text-" <> show (fromSqlKey k) <> "-" <> show n <> "\""

{- | The node-panel link as it appears in the rendered attribute.

Note the @&amp;@: Lucid escapes the ampersand between query parameters,
so the literal @&projectId=@ never appears in the document and asserting
on it silently matches nothing.
-}
panelLink :: Key M.Node -> Int64 -> String
panelLink k pid =
  "/ui/project/node/panel?nodeId="
    <> show (fromSqlKey k)
    <> "&amp;projectId="
    <> show pid

{- | @(node id, hue)@ for every disc in the document, read off the disc
groups in document order.

Parsing the markup rather than recomputing the hue: the point is that
what came out is self-consistent — every replica of a node in one
colour, different nodes in different ones — and asserting that against
a second copy of the formula would only prove the formula equals
itself.
-}
discHues :: String -> [(String, String)]
discHues body =
  [ (nodeId, hue)
  | tag <- tagsAfter "<g id=\"disc-" body
  , Just nodeId <- [attrOf "data-node-id" tag]
  , Just hue <- [attrOf "style" tag]
  ]

huesFor :: String -> String -> [String]
huesFor nodeId body = [h | (n, h) <- discHues body, n == nodeId]

-- | The text of each tag opened by @needle@, up to its closing @>@.
tagsAfter :: String -> String -> [String]
tagsAfter needle hay =
  [ takeWhile (/= '>') (drop (length needle) t)
  | t <- tails hay
  , needle `isPrefixOf` t
  ]

attrOf :: String -> String -> Maybe String
attrOf name tag =
  case [drop (length key) t | t <- tails tag, key `isPrefixOf` t] of
    (v : _) -> Just (takeWhile (/= '"') v)
    [] -> Nothing
  where
    key = name <> "=\""

shouldContainStr :: String -> String -> Expectation
shouldContainStr haystack needle =
  (needle `isInfixOf` haystack)
    `shouldSatisfyWith` ("expected the rendered graph to contain " <> show needle)

shouldNotContainStr :: String -> String -> Expectation
shouldNotContainStr haystack needle =
  not (needle `isInfixOf` haystack)
    `shouldSatisfyWith` ("expected the rendered graph not to contain " <> show needle)

countStr :: String -> String -> Int
countStr needle = length . filter (needle `isPrefixOf`) . tails

shouldSatisfyWith :: Bool -> String -> Expectation
shouldSatisfyWith True _ = pure ()
shouldSatisfyWith False msg = expectationFailure msg
