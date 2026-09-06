{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for 'handleProjectSubmit', building on the
infrastructure and pattern established in the pilot
('Domain.Project.Responder.Api.Node.PostSpec').

Unlike the other mutating-responder tests, this handler
doesn't mutate an existing 'M.Node' -- it's the flow that *creates* a
'M.Project' and its root 'M.Node' in the first place, so there's no
'Integration.Support.seedProjectWithRootNode' fixture to seed first;
it only needs the reference data ('withTestDatabase' already seeds
\"active\"\/\"project_root\") to exist.
-}
module Domain.Project.Responder.Ui.ProjectCreate.SubmitSpec (spec) where

import qualified Data.ByteString.Lazy.Char8 as LC8
import Database.Persist (Entity (..), Filter, count, selectList, (==.))
import Database.Persist.Sql (runSqlPool)
import qualified Domain.Project.Model as M
import Domain.Project.Responder.Ui.ProjectCreate.Submit (handleProjectSubmit, redirectHeader)
import Integration.Support (resetBetweenTests, withTestDatabase)
import Network.HTTP.Types (hContentType, methodPost)
import Network.Wai (defaultRequest, requestHeaders, requestMethod)
import Network.Wai.Test
  ( SRequest (..)
  , assertHeader
  , assertNoHeader
  , assertStatus
  , runSession
  , srequest
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestDatabase $
  beforeWith resetBetweenTests $
    describe "handleProjectSubmit (integration)" $ do
      it "creates a Project and a project_root Node for it" $ \pool -> do
        runSession
          ( do
              resp <- srequest $ submitRequest "ADescription" "ATitle"
              assertStatus 200 resp
              -- The Hx-Location redirect header is only ever set on
              -- the success path (see Submit.hs's `success` branch) --
              -- checking its exact value doubles as confirming the
              -- request actually took that branch, not just that it
              -- returned 200 (the validation-failure branch does too).
              uncurry assertHeader redirectHeader resp
          )
          (handleProjectSubmit pool)

        projectCount <- flip runSqlPool pool $ count ([] :: [Filter M.Project])
        projectCount `shouldBe` 1

        rootNodes <- flip runSqlPool pool $ selectList [M.NodeTitle ==. "ATitle"] []
        activeStatus <-
          flip runSqlPool pool $
            selectList [M.NodeStatusNodeStatusId ==. "active"] []
        rootType <-
          flip runSqlPool pool $
            selectList [M.NodeTypeNodeTypeId ==. "project_root"] []
        case (rootNodes, activeStatus, rootType) of
          ([Entity _ nd], [Entity activeKey _], [Entity rootTypeKey _]) -> do
            M.nodeDescription nd `shouldBe` "ADescription"
            M.nodeNodeStatusId nd `shouldBe` activeKey
            M.nodeNodeTypeId nd `shouldBe` rootTypeKey
          _ ->
            expectationFailure
              "expected exactly one root Node, and the seeded active/project_root rows"

      it "creates nothing when the payload is invalid" $ \pool -> do
        runSession
          ( do
              resp <- srequest $ submitRequest "" "ATitle"
              assertStatus 200 resp
              -- No redirect header on the validation-failure branch --
              -- distinguishes "form re-rendered" from "project created"
              -- since both return 200.
              assertNoHeader (fst redirectHeader) resp
          )
          (handleProjectSubmit pool)

        projectCount <- flip runSqlPool pool $ count ([] :: [Filter M.Project])
        projectCount `shouldBe` 0

submitRequest :: LC8.ByteString -> LC8.ByteString -> SRequest
submitRequest descr title =
  SRequest
    { simpleRequest =
        defaultRequest
          { requestMethod = methodPost
          , requestHeaders = [(hContentType, "application/x-www-form-urlencoded")]
          }
    , simpleRequestBody =
        "description="
          <> descr
          <> "&title="
          <> title
    }
