{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for 'handlePutDescription', building on the
infrastructure and pattern established in the pilot
('Domain.Project.Responder.Api.Node.PostSpec').
-}
module Domain.Project.Responder.Ui.ProjectManage.Node.DescriptionSpec (spec) where

import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.Int (Int64)
import Database.Persist (get)
import Database.Persist.Sql (fromSqlKey, runSqlPool)
import qualified Domain.Project.Model as M
import Domain.Project.Responder.Ui.ProjectManage.Node.Description (handlePutDescription)
import Integration.Support
  ( resetBetweenTests
  , seedProjectWithRootNode
  , withTestDatabase
  )
import Network.HTTP.Types (hContentType, methodPut)
import Network.Wai (defaultRequest, requestHeaders, requestMethod)
import Network.Wai.Test
  ( SRequest (..)
  , assertStatus
  , runSession
  , srequest
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestDatabase $
  beforeWith resetBetweenTests $
    describe "handlePutDescription (integration)" $ do
      it "replaces the Node's description in the database" $ \pool -> do
        (projectKey, rootKey) <- seedProjectWithRootNode pool

        runSession
          ( do
              resp <-
                srequest $
                  putDescriptionRequest
                    (fromSqlKey rootKey)
                    (fromSqlKey projectKey)
                    "UpdatedDescription"
              assertStatus 200 resp
          )
          (handlePutDescription pool)

        updated <- flip runSqlPool pool $ get rootKey
        case updated of
          Just nd -> M.nodeDescription nd `shouldBe` "UpdatedDescription"
          Nothing -> expectationFailure "expected the root Node to still exist"

      it "returns 404 when the node doesn't exist" $ \pool ->
        runSession
          ( do
              resp <- srequest $ putDescriptionRequest 999999 999999 "desc"
              assertStatus 404 resp
          )
          (handlePutDescription pool)

putDescriptionRequest :: Int64 -> Int64 -> LC8.ByteString -> SRequest
putDescriptionRequest nodeId projectId descr =
  SRequest
    { simpleRequest =
        defaultRequest
          { requestMethod = methodPut
          , requestHeaders = [(hContentType, "application/x-www-form-urlencoded")]
          }
    , simpleRequestBody =
        "description="
          <> descr
          <> "&nodeId="
          <> LC8.pack (show nodeId)
          <> "&projectId="
          <> LC8.pack (show projectId)
    }
