{-# LANGUAGE OverloadedStrings #-}

module App.LinkSpec (spec) where

import App.Link
import Config.Visualization (Visualization (..))
import Test.Hspec

spec :: Spec
spec = do
  -- These strings land in htmx attributes, so a change in what safeLink
  -- renders is a change in what the browser requests. The cases pin the
  -- shape: an absolute path, and query parameters in the order the route
  -- type declares them.
  describe "static links" $ do
    it "renders a bare route as an absolute path" $
      emptyLink `shouldBe` "/ui/central/empty"

    it "renders the project index" $
      projectIndexLink `shouldBe` "/ui/projects/vw"

    it "renders the project list fragment" $
      projectListLink `shouldBe` "/ui/projects/list"

    it "renders the create-project view and its submit target" $ do
      createProjectLink `shouldBe` "/ui/create-project/vw"
      createProjectSubmitLink `shouldBe` "/ui/create-project/submit"

    it "renders the node field-update routes" $ do
      nodeTitleLink `shouldBe` "/ui/project/node/title"
      nodeDescriptionLink `shouldBe` "/ui/project/node/description"
      nodeStatusLink `shouldBe` "/ui/project/node/status"

    it "renders the add-work submit target without its query parameter" $
      addWorkSubmitLink `shouldBe` "/ui/project/node/create"

  describe "parameterised links" $ do
    it "renders a required parameter" $ do
      projectStatsLink 7 `shouldBe` "/ui/project/stats?projectId=7"
      addWorkLink 7 `shouldBe` "/ui/project/node/create?projectId=7"

    it "orders node parameters as the route declares them" $ do
      nodePanelLink 3 7 `shouldBe` "/ui/project/node/panel?projectId=7&nodeId=3"
      nodeDetailLink 3 7 `shouldBe` "/ui/project/node/detail?projectId=7&nodeId=3"
      editLink 3 7 `shouldBe` "/ui/project/node/edit?projectId=7&nodeId=3"

    it "omits an absent optional parameter" $ do
      graphLinkFor 7 `shouldBe` "/ui/project/graph?projectId=7"
      projectLink 7 `shouldBe` "/ui/project/vw?projectId=7"

    it "includes an optional parameter that is present" $ do
      graphLink 7 Rootless
        `shouldBe` "/ui/project/graph?projectId=7&visualizationMode=Rootless"
      projectViewLink 7 (Just 3) (Just Orbital)
        `shouldBe` "/ui/project/vw?projectId=7&nodeId=3&visualizationMode=Orbital"

    -- The client title is a node title read off the page, so it can hold
    -- characters that would otherwise end the parameter.
    it "escapes a free-text parameter" $
      nodeRefreshLink 3 7 120 "Ship it & bill it"
        `shouldBe` "/ui/project/node/refresh?projectId=7&nodeId=3\
                   \&clientTitle=Ship%20it%20%26%20bill%20it&wrapWidth=120"

    it "points a created node at its collection" $
      nodeResourceLink 42 `shouldBe` "/api/project/nodes/42"
