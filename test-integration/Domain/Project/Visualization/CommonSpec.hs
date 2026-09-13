{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for the visualization switch.

Which drawing to render is a property of the /request/: an optional
@visualizationMode@ query parameter, defaulting to
'defaultVisualization' when absent. Nothing about it is read from the
environment, so none of this belongs in @Config.AppSpec@.

The point of testing it at this tier rather than by calling
'Config.Visualization.parseVisualization' directly is that the
interesting failure is not "does the string parse" but "does the right
drawing come back". So each case asserts on the rendered markup, and
the drawings are told apart by things only one of them emits.

A value that names no visualization is refused with a 400 rather than
corrected, so those cases assert on the status instead. Casing is not
such a value: the vocabulary is stated explicitly and parsed
case-insensitively, so a wrong-cased constructor is simply accepted.

This drives the route, not a copy of its dispatch table: a spec with
its own table would keep passing if the application's table lost an
entry.
-}
module Domain.Project.Visualization.CommonSpec (spec) where

import Config.Visualization (defaultVisualization)
import Data.Int (Int64)
import Data.Text (Text, pack)
import Database.Persist.Sql (fromSqlKey)
import Integration.Support
  ( TestApp
  , bodyOf
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
    describe "the visualizationMode switch (integration)" $ do
      it "serves the rootless drawing when asked for it" $ \ta -> do
        pid <- fixture ta
        body <- graphBody ta (graphUrl pid <> "&visualizationMode=Rootless")

        -- Rects, from the shared layout engine. The project root is
        -- absent by design and no containment edge is derived to reach
        -- the work: the dependencies are the whole drawing.
        body `shouldContainStr` "<rect class=\"work"
        body `shouldNotContainStr` "<rect class=\"root"
        body `shouldNotContainStr` "link-contains"

      it "serves the orbital drawing when asked for it" $ \ta -> do
        pid <- fixture ta
        body <- graphBody ta (graphUrl pid <> "&visualizationMode=Orbital")

        -- Circles rather than rects: a different geometry entirely.
        body `shouldContainStr` "<circle class=\"work"
        body `shouldNotContainStr` "<rect class=\"work"

      it "falls back to the default when the parameter is absent" $ \ta -> do
        -- Asserted against `defaultVisualization` rather than against
        -- whichever drawing that happens to be today. The convention is
        -- "whichever visualization was added most recently", so the
        -- answer changes; that it agrees with the binding should not.
        pid <- fixture ta
        implicit <- graphBody ta (graphUrl pid)
        explicit <-
          graphBody ta (graphUrl pid <> "&visualizationMode=" <> defaultMode)

        implicit `shouldBe` explicit

      it "accepts a known visualization in the wrong case" $ \ta -> do
        -- The vocabulary is stated explicitly and matched
        -- case-insensitively, so casing is not a way to get this
        -- parameter wrong.
        pid <- fixture ta
        lower <- graphBody ta (graphUrl pid <> "&visualizationMode=rootless")
        exact <- graphBody ta (graphUrl pid <> "&visualizationMode=Rootless")

        lower `shouldBe` exact

      it "refuses a value that names no visualization" $ \ta -> do
        pid <- fixture ta
        resp <- httpGet ta (graphUrl pid <> "&visualizationMode=Radial")

        statusOf resp `shouldBe` 400

      it "refuses an empty value rather than treating it as absent" $ \ta -> do
        -- `?visualizationMode=` is a value that is present and does not
        -- parse, not a missing one. The parameter is Strict, so it is
        -- refused rather than silently defaulted.
        pid <- fixture ta
        resp <- httpGet ta (graphUrl pid <> "&visualizationMode=")

        statusOf resp `shouldBe` 400

      it "refuses a project id that is not a number" $ \ta -> do
        resp <- httpGet ta "/ui/project/graph?projectId=0x1"

        statusOf resp `shouldBe` 400

      it "refuses a missing project id" $ \ta -> do
        resp <- httpGet ta "/ui/project/graph"

        statusOf resp `shouldBe` 400

      -- The drawing is of the project's nodes, so a project with none
      -- is a 404 rather than an empty canvas.
      it "answers a project with no nodes with a 404" $ \ta -> do
        resp <- httpGet ta (graphUrl 999999)

        statusOf resp `shouldBe` 404

{- | A project with a root, two work nodes and a real dependency --
enough for every drawing to render something distinguishable.
-}
fixture :: TestApp -> IO Int64
fixture ta = do
  (projectKey, _) <- seedProjectWithRootNode ta
  a <- seedWorkNode ta projectKey "First"
  b <- seedWorkNode ta projectKey "Second"
  seedDependency ta a b
  pure (fromSqlKey projectKey)

graphBody :: TestApp -> Text -> IO String
graphBody ta url = do
  resp <- httpGet ta url
  statusOf resp `shouldBe` 200
  pure (bodyOf resp)

graphUrl :: Int64 -> Text
graphUrl pid = "/ui/project/graph?projectId=" <> pack (show pid)

defaultMode :: Text
defaultMode = pack (show defaultVisualization)
