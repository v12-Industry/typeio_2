{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for the node chrome the server-computed graph
renders.

These assertions are deliberately about markup rather than geometry.
The layout engine's own output is unit-tested
(@test\/Domain\/Project\/Graph\/@); what has no coverage below that
line is the contract between the rendered SVG and everything bound to
it -- @manage-project.css@ styles nodes off the @root@\/@work@ class,
the per-node refresh hook swaps into @#node-text-\<id\>@, and
@e2e\/tests\/graph.spec.ts@ finds nodes by @#node-\<id\>@. Each of
those is a string in one file matching a string in another: exactly
the pairing a compiler cannot check and a rename silently breaks.

See @docs\/architecture\/graph-rendering.md@ ("The DOM contract").
-}
module Domain.Project.Responder.Ui.ProjectManage.GraphSpec (spec) where

import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.Int (Int64)
import Data.List (isInfixOf, isPrefixOf, tails)
import Database.Persist.Sql (ConnectionPool, fromSqlKey)
import Domain.Project.Visualization.Layered.Responder (handleProjectGraph)
import Integration.Support
  ( resetBetweenTests
  , seedDependency
  , seedProjectWithRootNode
  , seedWorkNode
  , withTestDatabase
  )
import Network.HTTP.Types (Query, methodGet)
import Network.Wai (Request, defaultRequest, queryString, requestMethod)
import Network.Wai.Test
  ( SResponse (..)
  , assertStatus
  , request
  , runSession
  )
import Test.Hspec
import Text.Read (readMaybe)

spec :: Spec
spec = aroundAll withTestDatabase $
  beforeWith resetBetweenTests $
    describe "handleProjectGraph (integration)" $ do
      describe "server-computed layout" $ do
        it "draws each node as a rounded rect classed by its kind" $ \pool -> do
          (projectKey, rootKey) <- seedProjectWithRootNode pool
          workKey <- seedWorkNode pool projectKey "Build the thing"
          seedDependency pool rootKey workKey

          body <- serverGraphBody pool (fromSqlKey projectKey)

          -- The root and the work node come off the same template and
          -- are told apart only by this class, which is what
          -- `#tree-container .node .root` / `.work` colour, hover and
          -- glow.
          body `shouldContainStr` "<rect class=\"root\""
          body `shouldContainStr` "<rect class=\"work\""
          -- Rounded, per the reference images' shape.
          body `shouldContainStr` "rx=\"6\""
          -- ...and no circles: this renderer draws rects only.
          body `shouldNotContainStr` "<circle"

        it "leaves the node's fill and stroke to the stylesheet" $ \pool -> do
          (projectKey, _) <- seedProjectWithRootNode pool

          body <- serverGraphBody pool (fromSqlKey projectKey)

          -- A `stroke` presentation attribute on the rect would still
          -- render, but it splits the node's appearance across two
          -- files and silently drops out of any theme change. The
          -- class is the whole styling surface.
          body `shouldNotContainStr` "<rect class=\"root\" stroke"
          body `shouldNotContainStr` "fill=\"white\""

        it "gives every node label its own id, matching the refresh hook" $ \pool -> do
          (projectKey, rootKey) <- seedProjectWithRootNode pool
          workKey <- seedWorkNode pool projectKey "Build the thing"
          seedDependency pool rootKey workKey

          body <- serverGraphBody pool (fromSqlKey projectKey)

          -- Per-node, not a constant: this element used to be emitted
          -- as a fixed `node-label` on every node, which both repeated
          -- one id throughout the document and left the hook below
          -- aimed at a target that did not exist.
          mapM_
            (shouldContainStr body . nodeTextId)
            [fromSqlKey rootKey, fromSqlKey workKey]
          body `shouldNotContainStr` "id=\"node-label\""

          -- The hook and its target have to name the same element.
          -- They sit ~40 lines apart in one module and nothing else
          -- checks that they still agree.
          mapM_
            (shouldContainStr body . nodeTextTarget)
            [fromSqlKey rootKey, fromSqlKey workKey]

        it "points the refresh hook at the refresh endpoint" $ \pool -> do
          (projectKey, _) <- seedProjectWithRootNode pool

          body <- serverGraphBody pool (fromSqlKey projectKey)

          -- No `layout=server` on this link: one renderer, so one wrap
          -- width, so nothing left to tell the endpoint apart from the
          -- node itself.
          body `shouldContainStr` "/ui/project/node/refresh?nodeId="
          body `shouldNotContainStr` "layout=server"

          body `shouldContainStr` "wrapWidth=18"
          body `shouldNotContainStr` "wrapWidth=12"

      describe "the node-identity contract" $ do
        it "tags every drawn node with the node it stands for" $ \pool -> do
          -- The one thing a visualization has to publish for the rest
          -- of the Project Manage UI to work with it. The panel
          -- highlight and the post-edit flash both select on this.
          (projectKey, rootKey) <- seedProjectWithRootNode pool
          workKey <- seedWorkNode pool projectKey "Build the thing"

          body <- serverGraphBody pool (fromSqlKey projectKey)

          body `shouldContainStr` dataNodeId (fromSqlKey rootKey)
          body `shouldContainStr` dataNodeId (fromSqlKey workKey)

        it "keeps #node-<id> alongside it" $ \pool -> do
          -- Additive, not a replacement: graph-rendering.md lists the
          -- id as a contract and graph.spec.ts locates nodes by it.
          (projectKey, rootKey) <- seedProjectWithRootNode pool

          body <- serverGraphBody pool (fromSqlKey projectKey)

          body
            `shouldContainStr` ("id=\"node-" <> show (fromSqlKey rootKey) <> "\"")

      describe "viewport" $ do
        it "emits the drawing's natural size" $ \pool -> do
          (projectKey, rootKey) <- seedProjectWithRootNode pool
          workKey <- seedWorkNode pool projectKey "Build the thing"
          seedDependency pool rootKey workKey

          body <- serverGraphBody pool (fromSqlKey projectKey)

          -- The SVG is sized in percentages, so its own attributes no
          -- longer say how big the drawing actually is. The viewport
          -- needs that to centre a project with no root, and to restore
          -- a usable size if the d3 bundle fails to load.
          body `shouldContainStr` "data-base-width="
          body `shouldContainStr` "data-base-height="

        it "emits where the project root landed" $ \pool -> do
          (projectKey, rootKey) <- seedProjectWithRootNode pool
          workKey <- seedWorkNode pool projectKey "Build the thing"
          seedDependency pool rootKey workKey

          body <- serverGraphBody pool (fromSqlKey projectKey)

          -- The server placed the root, so the client never searches
          -- the DOM for it. Emitted relative to the drawing's top-left,
          -- which is the zoom layer's own coordinate system, so the
          -- client centres it with a translate and no further
          -- arithmetic.
          body `shouldContainStr` "data-root-x="
          body `shouldContainStr` "data-root-y="

        it "ships the zoom layer and the viewport script with the graph" $ \pool -> do
          (projectKey, _) <- seedProjectWithRootNode pool

          body <- serverGraphBody pool (fromSqlKey projectKey)

          -- Both are inside the swapped fragment: #tree-container is
          -- replaced wholesale on every graph load, so anything bound
          -- to the drawing has to arrive with it.
          body `shouldContainStr` "id=\"graph-zoom-layer\""
          body `shouldContainStr` "/static/script/graph-viewport.js"

        it "ships no on-screen zoom controls" $ \pool -> do
          (projectKey, _) <- seedProjectWithRootNode pool

          body <- serverGraphBody pool (fromSqlKey projectKey)

          -- Gestures, not a button cluster. The drawing is what the
          -- viewport is for; three permanent buttons sitting on top of
          -- it are what it is not.
          body `shouldNotContainStr` "id=\"graph-zoom-in\""
          body `shouldNotContainStr` "id=\"graph-zoom-out\""
          body `shouldNotContainStr` "id=\"graph-zoom-reset\""
          body `shouldNotContainStr` "graph-controls"

        it "names no script but its own -- d3 arrives only inside it" $ \pool -> do
          (projectKey, _) <- seedProjectWithRootNode pool

          body <- serverGraphBody pool (fromSqlKey projectKey)

          -- d3 is reached by a dynamic import inside
          -- graph-viewport.js, and must not appear in any markup the
          -- server emits -- not as a <script> here, and not as an
          -- inlined bundle. It is never loaded app-wide.
          --
          -- This is the tripwire that would catch d3 being promoted
          -- back to something the page itself pulls in, which is how
          -- it got onto every page in the app last time.
          body `shouldNotContainStr` "d3"

      describe "containment" $ do
        it "draws the project root above its work" $ \pool -> do
          (projectKey, _) <- seedProjectWithRootNode pool
          _ <- seedWorkNode pool projectKey "Build the thing"
          _ <- seedWorkNode pool projectKey "Build another thing"

          body <- graphBody pool (fromSqlKey projectKey) []

          -- The root's box must have the smallest y of any node.
          -- Hand membership to the engine as a dependency and the
          -- engine, working correctly, sinks the root below everything
          -- in the project. This is the assertion that catches that.
          let rootTops = nodeTops "root" body
              workTops = nodeTops "work" body
          length rootTops `shouldBe` 1
          length workTops `shouldBe` 2
          all (> maximum rootTops) workTops `shouldBe` True

        it "derives containment rather than reading a dependency row" $ \pool -> do
          (projectKey, _) <- seedProjectWithRootNode pool
          _ <- seedWorkNode pool projectKey "Build the thing"

          body <- graphBody pool (fromSqlKey projectKey) []

          -- No dependency rows are seeded here at all, yet the graph
          -- still connects the root to its work: the edge comes from
          -- `node.project_id`, not from `project.dependency`.
          body `shouldContainStr` "class=\"link link-contains\""

        it "gives a containment edge an arrowhead too" $ \pool -> do
          (projectKey, _) <- seedProjectWithRootNode pool
          _ <- seedWorkNode pool projectKey "Build the thing"

          body <- graphBody pool (fromSqlKey projectKey) []

          -- A project's completion depends on its work being complete,
          -- so the root is waiting on every node under it and the edge
          -- carries the same arrow as any dependency. Its head
          -- lands on the root, which `LayoutSpec` pins geometrically.
          body `shouldContainStr` "link-contains"
          body `shouldContainStr` "marker-end"

        it "gives a real dependency its arrowhead" $ \pool -> do
          -- The positive case. Asserting only the *absence* of an
          -- arrow elsewhere would let an inverted condition in the
          -- renderer go unnoticed.
          (projectKey, rootKey) <- seedProjectWithRootNode pool
          workKey <- seedWorkNode pool projectKey "Build the thing"
          seedDependency pool rootKey workKey

          body <- graphBody pool (fromSqlKey projectKey) []

          -- A stored row recording that the root waits on this work,
          -- drawn with a head. No containment edge is derived beside
          -- it: the root already sits above that node, so a second
          -- edge saying so would be redundant.
          body `shouldContainStr` "class=\"link\""
          body `shouldContainStr` "marker-end=\"url(#arrow)\""

      describe "containment reaches the work through its own shape" $ do
        it "attaches the root to a chain's head only" $ \pool -> do
          -- The bug as reported: on a chain, every node got its own
          -- root edge on top of the chain that already described the
          -- work, so the root fanned out to all of them and the real
          -- shape was buried underneath.
          (projectKey, _) <- seedProjectWithRootNode pool
          a <- seedWorkNode pool projectKey "First"
          b <- seedWorkNode pool projectKey "Second"
          c <- seedWorkNode pool projectKey "Third"
          -- b waits on a, c waits on b.
          seedDependency pool b a
          seedDependency pool c b

          body <- graphBody pool (fromSqlKey projectKey) []

          -- One derived edge, to the head, and the two stored ones.
          countStr "link link-contains" body `shouldBe` 1
          countStr "class=\"link\"" body `shouldBe` 2

        it "still attaches work that nothing depends on" $ \pool -> do
          -- The other half of the rule: a node with no dependencies at
          -- all is its own head, so it keeps its root edge rather than
          -- floating away from the project.
          (projectKey, _) <- seedProjectWithRootNode pool
          a <- seedWorkNode pool projectKey "Chained"
          b <- seedWorkNode pool projectKey "Chained too"
          _ <- seedWorkNode pool projectKey "On its own"
          seedDependency pool b a

          body <- graphBody pool (fromSqlKey projectKey) []

          -- The chain's head, and the lone node.
          countStr "link link-contains" body `shouldBe` 2

      describe "the server-computed cutover" $ do
        it "serves the computed layout with no query parameter" $ \pool -> do
          (projectKey, _) <- seedProjectWithRootNode pool

          -- No flag. This is the assertion the whole effort was for.
          body <- graphBody pool (fromSqlKey projectKey) []

          body `shouldContainStr` "<rect class=\"root\""
          body `shouldContainStr` "/static/script/graph-viewport.js"

        it "leaves no trace of the client-rendered path behind" $ \pool -> do
          (projectKey, rootKey) <- seedProjectWithRootNode pool
          workKey <- seedWorkNode pool projectKey "Build the thing"
          seedDependency pool rootKey workKey

          body <- graphBody pool (fromSqlKey projectKey) []

          -- The graph never leaves the server as data at all: it
          -- leaves as finished SVG, so there is nothing for a client
          -- layout script to read.
          body `shouldNotContainStr` "graph-data"
          body `shouldNotContainStr` "nodetree"
          body `shouldNotContainStr` "<circle"
          body `shouldNotContainStr` "zoom-group"

        it "ignores a leftover ?layout=server rather than branching on it" $ \pool -> do
          (projectKey, _) <- seedProjectWithRootNode pool

          -- A bookmarked URL from while the flag existed must not select
          -- some other renderer, because there isn't one -- the
          -- parameter is now just an unread query string.
          flagged <- serverGraphBody pool (fromSqlKey projectKey)
          plain <- graphBody pool (fromSqlKey projectKey) []
          flagged `shouldBe` plain

-- | GET the graph view with @?layout=server@.
serverGraphBody :: ConnectionPool -> Int64 -> IO String
serverGraphBody pool pid =
  graphBody pool pid [("layout", Just "server")]

-- | GET the graph view and hand its body back as a searchable 'String'.
graphBody :: ConnectionPool -> Int64 -> Query -> IO String
graphBody pool pid extraQuery =
  runSession
    ( do
        resp <- request (graphRequest pid extraQuery)
        assertStatus 200 resp
        pure . LC8.unpack . simpleBody $ resp
    )
    (handleProjectGraph pool)

graphRequest :: Int64 -> Query -> Request
graphRequest pid extraQuery =
  defaultRequest
    { requestMethod = methodGet
    , queryString =
        ("projectId", Just . C8.pack . show $ pid) : extraQuery
    }

shouldContainStr :: String -> String -> Expectation
shouldContainStr haystack needle =
  (needle `isInfixOf` haystack)
    `shouldSatisfyWith` ("expected the rendered graph to contain " <> show needle)

shouldNotContainStr :: String -> String -> Expectation
shouldNotContainStr haystack needle =
  not (needle `isInfixOf` haystack)
    `shouldSatisfyWith` ("expected the rendered graph not to contain " <> show needle)

{- | How many times @needle@ occurs in @haystack@, counting overlaps.

Presence alone is not enough for the containment rule: a root drawing
an edge to /every/ node rather than to the heads passes
`shouldContainStr` just as happily as a correct one. What is being
asserted is a count.
-}
countStr :: String -> String -> Int
countStr needle = length . filter (needle `isPrefixOf`) . tails

{- | A plain 'shouldBe' on a 'Bool' reports "False /= True", which says
nothing about which string was missing; this keeps the needle in the
failure message.
-}
shouldSatisfyWith :: Bool -> String -> Expectation
shouldSatisfyWith True _ = pure ()
shouldSatisfyWith False msg = expectationFailure msg

dataNodeId :: Int64 -> String
dataNodeId nid = "data-node-id=\"" <> show nid <> "\""

nodeTextId :: Int64 -> String
nodeTextId nid = "id=\"node-text-" <> show nid <> "\""

nodeTextTarget :: Int64 -> String
nodeTextTarget nid = "hx-target=\"#node-text-" <> show nid <> "\""

{- | The @y@ of every node group whose rect carries the given kind
class, read straight out of the rendered SVG.

Deliberately parsing the markup rather than calling @layout@ directly:
the layout engine's own placement is unit-tested, and what these pin
is the /responder's/ conversion — which relationship it hands the
engine. That only shows up in the finished document.

Each node renders as
@\<g id="node-N" class="node" transform="translate(X,Y)"\>\<rect class="KIND"@,
so splitting on the group and reading forward is enough; no HTML parser
required for a shape this fixed.
-}
nodeTops :: String -> String -> [Double]
nodeTops kind body =
  [ y
  | chunk <- drop 1 (splitOn "<g id=\"node-" body)
  , ("class=\"" <> kind <> "\"") `isInfixOf` takeWhile (/= '>') (dropToRect chunk)
  , Just y <- [translateY chunk]
  ]
  where
    dropToRect = afterFirst "<rect "
    translateY chunk = case afterFirst "transform=\"translate(" chunk of
      "" -> Nothing
      rest -> case break (== ',') (takeWhile (/= ')') rest) of
        (_, ',' : ys) -> readMaybe ys
        _ -> Nothing

-- | Everything after the first occurrence of @needle@, or @""@.
afterFirst :: String -> String -> String
afterFirst needle hay = case splitOn needle hay of
  (_ : rest : _) -> rest
  _ -> ""

splitOn :: String -> String -> [String]
splitOn needle = go
  where
    go hay
      | null hay = [""]
      | needle `isPrefixOf` hay = "" : go (drop (length needle) hay)
      | otherwise = case go (drop 1 hay) of
          (c : cs) -> (head hay : c) : cs
          [] -> [[head hay]]
