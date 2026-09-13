{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for @POST /ui/create-project/submit@.

Unlike the other mutating routes, this one doesn't mutate an existing
'M.Node' -- it's the flow that *creates* a 'M.Project' and its root
'M.Node' in the first place, so there's no
'Integration.Support.seedProjectWithRootNode' fixture to seed first;
it only needs the reference data ('withTestApp' already seeds
\"active\"\/\"project_root\") to exist.
-}
module Domain.Project.Responder.Ui.ProjectCreate.SubmitSpec (spec) where

import qualified Data.ByteString.Char8 as C8
import Database.Persist (Entity (..), Filter, count, selectList, (==.))
import Database.Persist.Sql (runSqlPool)
import qualified Domain.Project.Model as M
import Integration.Support
  ( SResponse
  , TestApp (..)
  , formBody
  , headerOf
  , httpPost
  , resetBetweenTests
  , statusOf
  , withTestApp
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestApp $
  beforeWith resetBetweenTests $
    describe "POST /ui/create-project/submit (integration)" $ do
      it "creates a Project and a project_root Node for it" $ \ta -> do
        resp <- submit ta "ADescription" "ATitle"
        statusOf resp `shouldBe` 200
        -- The HX-Location redirect header is only ever set on the
        -- success path, so checking it doubles as confirming the
        -- request took that branch rather than just returning 200 (the
        -- validation-failure branch does too).
        headerOf "HX-Location" resp
          `shouldBe` Just "{\"path\":\"/ui/projects/vw\",\"target\":\"#container\"}"

        projectCount <- flip runSqlPool (testPool ta) $ count ([] :: [Filter M.Project])
        projectCount `shouldBe` 1

        rootNodes <- flip runSqlPool (testPool ta) $ selectList [M.NodeTitle ==. "ATitle"] []
        activeStatus <-
          flip runSqlPool (testPool ta) $
            selectList [M.NodeStatusNodeStatusId ==. "active"] []
        rootType <-
          flip runSqlPool (testPool ta) $
            selectList [M.NodeTypeNodeTypeId ==. "project_root"] []
        case (rootNodes, activeStatus, rootType) of
          ([Entity _ nd], [Entity activeKey _], [Entity rootTypeKey _]) -> do
            M.nodeDescription nd `shouldBe` "ADescription"
            M.nodeNodeStatusId nd `shouldBe` activeKey
            M.nodeNodeTypeId nd `shouldBe` rootTypeKey
          _ ->
            expectationFailure
              "expected exactly one root Node, and the seeded active/project_root rows"

      it "creates nothing when the payload is invalid" $ \ta -> do
        resp <- submit ta "" "ATitle"
        statusOf resp `shouldBe` 200
        -- No redirect header on the validation-failure branch --
        -- distinguishes "form re-rendered" from "project created"
        -- since both return 200.
        headerOf "HX-Location" resp `shouldBe` Nothing

        projectCount <- flip runSqlPool (testPool ta) $ count ([] :: [Filter M.Project])
        projectCount `shouldBe` 0

submit :: TestApp -> C8.ByteString -> C8.ByteString -> IO SResponse
submit ta descr title =
  httpPost
    ta
    "/ui/create-project/submit"
    (formBody [("description", descr), ("title", title)])
