{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for the visualization switch (#223).

Which drawing to render is a property of the /request/ now, not of the
process: an optional @visualizationMode@ query parameter, defaulting to
'defaultVisualization' when absent. Before #223 it was
@GRAPH_VISUALIZATION@, read once at boot, and the equivalent coverage
lived in @Config.AppSpec@ — those four cases moved here with the
mechanism.

The point of testing it at this tier rather than by calling
'validateVisualization' directly is that the interesting failure is not
"does the string parse" but "does the right drawing come back". So each
case asserts on the rendered markup, and the three drawings are told
apart by things only one of them emits.

This deliberately drives 'handleGraph' with the real
'Domain.Project.Responder.Ui.Container.renderFor' table, not a copy: a
spec with its own table would keep passing if the app's table lost an
entry.
-}
module Domain.Project.Visualization.CommonSpec (spec) where

import Config.Visualization (defaultVisualization)
import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.Int (Int64)
import Data.List (isInfixOf)
import Database.Persist.Sql (ConnectionPool, fromSqlKey)
import Domain.Project.Responder.Ui.Container (renderFor)
import Domain.Project.Visualization.Common (handleGraph)
import Integration.Support
  ( resetBetweenTests
  , seedDependency
  , seedProjectWithRootNode
  , seedWorkNode
  , withTestDatabase
  )
import Network.HTTP.Types (Query, methodGet, status200, status403)
import Network.Wai (Request, defaultRequest, queryString, requestMethod)
import Network.Wai.Test
  ( SResponse (..)
  , request
  , runSession
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestDatabase $
  beforeWith resetBetweenTests $
    describe "handleGraph, the visualizationMode switch (integration)" $ do
      it "serves the layered drawing when asked for it" $ \pool -> do
        pid <- fixture pool
        body <- graphBody pool pid [("visualizationMode", Just "Layered")]

        -- Only the layered drawing keeps the project root, and only it
        -- derives a containment edge to reach the work.
        body `shouldContainStr` "<rect class=\"root\""
        body `shouldContainStr` "link-contains"

      it "serves the rootless drawing when asked for it" $ \pool -> do
        pid <- fixture pool
        body <- graphBody pool pid [("visualizationMode", Just "Rootless")]

        -- Layered geometry (rects) but no root, which is the whole of
        -- what distinguishes it from the case above.
        body `shouldContainStr` "<rect class=\"work\""
        body `shouldNotContainStr` "<rect class=\"root\""

      it "serves the orbital drawing when asked for it" $ \pool -> do
        pid <- fixture pool
        body <- graphBody pool pid [("visualizationMode", Just "Orbital")]

        -- Circles rather than rects: a different geometry entirely.
        body `shouldContainStr` "<circle class=\"work\""
        body `shouldNotContainStr` "<rect class=\"work\""

      it "falls back to the default when the parameter is absent" $ \pool -> do
        -- Asserted against `defaultVisualization` rather than against
        -- whichever drawing that happens to be today. The convention is
        -- "whichever visualization was added most recently", so the
        -- answer changes; that it agrees with the binding should not.
        pid <- fixture pool
        implicit <- graphBody pool pid []
        explicit <-
          graphBody
            pool
            pid
            [("visualizationMode", Just (C8.pack (show defaultVisualization)))]

        implicit `shouldBe` explicit

      it "rejects an empty parameter rather than treating it as absent" $ \pool -> do
        -- `?visualizationMode=` is a value that is present and does not
        -- parse, not a missing one -- `lookupVal` returns `Just ""` and
        -- `valRead` rejects it.
        --
        -- Asserted because the friendlier reading is tempting and would
        -- be inconsistent: every other optional query parameter in this
        -- app behaves this way already (`?nodeId=` is rejected by
        -- ProjectManage.View's own valRead). Special-casing this one
        -- field would make "empty" mean something different depending
        -- on which parameter you left blank.
        pid <- fixture pool
        resp <- graphResponse pool pid [("visualizationMode", Just "")]

        simpleStatus resp `shouldBe` status403

      it "rejects a value that names no visualization" $ \pool -> do
        -- The half of the old GRAPH_VISUALIZATION behaviour worth
        -- keeping: a value somebody got wrong fails loudly rather than
        -- falling back, since a silently defaulted visualization
        -- surfaces much later as "the graph looks wrong".
        pid <- fixture pool
        resp <- graphResponse pool pid [("visualizationMode", Just "Radial")]

        simpleStatus resp `shouldBe` status403
        LC8.unpack (simpleBody resp)
          `shouldContainStr` "Invalid visualizationMode value"

      it "rejects a known constructor in the wrong case" $ \pool -> do
        -- `Read` is case-sensitive on constructor names, the same way
        -- ENV is (see Common.ValidationSpec). Worth pinning: this is
        -- the most likely way to get the parameter wrong by hand.
        pid <- fixture pool
        resp <- graphResponse pool pid [("visualizationMode", Just "orbital")]

        simpleStatus resp `shouldBe` status403

{- | A project with a root, two work nodes and a real dependency —
enough for every drawing to render something distinguishable.
-}
fixture :: ConnectionPool -> IO Int64
fixture pool = do
  (projectKey, _) <- seedProjectWithRootNode pool
  a <- seedWorkNode pool projectKey "First"
  b <- seedWorkNode pool projectKey "Second"
  seedDependency pool a b
  pure (fromSqlKey projectKey)

graphBody :: ConnectionPool -> Int64 -> Query -> IO String
graphBody pool pid extra = do
  resp <- graphResponse pool pid extra
  simpleStatus resp `shouldBe` status200
  pure . LC8.unpack . simpleBody $ resp

graphResponse :: ConnectionPool -> Int64 -> Query -> IO SResponse
graphResponse pool pid extra =
  runSession (request (graphRequest pid extra)) (handleGraph renderFor pool)

graphRequest :: Int64 -> Query -> Request
graphRequest pid extra =
  defaultRequest
    { requestMethod = methodGet
    , queryString = ("projectId", Just . C8.pack . show $ pid) : extra
    }

shouldContainStr :: String -> String -> Expectation
shouldContainStr haystack needle =
  if needle `isInfixOf` haystack
    then pure ()
    else expectationFailure ("expected the response to contain " <> show needle)

shouldNotContainStr :: String -> String -> Expectation
shouldNotContainStr haystack needle =
  if needle `isInfixOf` haystack
    then expectationFailure ("expected the response not to contain " <> show needle)
    else pure ()
