{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for 'handlePutNodeStatus', building on the
infrastructure and pattern established in the pilot
('Domain.Project.Responder.Api.Node.PostSpec').
-}
module Domain.Project.Responder.Ui.ProjectManage.Node.StatusSpec (spec) where

import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.Int (Int64)
import Data.List (isInfixOf)
import Database.Persist (Entity (..), get, selectList, (==.))
import Database.Persist.Sql (fromSqlKey, runSqlPool)
import qualified Domain.Project.Model as M
import Domain.Project.Responder.Ui.ProjectManage.Node.Status (handlePutNodeStatus)
import Integration.Support
  ( resetBetweenTests
  , seedProjectWithRootNode
  , withTestDatabase
  )
import Network.HTTP.Types (hContentType, methodPut)
import Network.Wai (defaultRequest, requestHeaders, requestMethod)
import Network.Wai.Test
  ( SRequest (..)
  , SResponse (..)
  , assertStatus
  , runSession
  , srequest
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestDatabase $
  beforeWith resetBetweenTests $
    describe "handlePutNodeStatus (integration)" $ do
      it "replaces the Node's status in the database" $ \pool -> do
        (projectKey, rootKey) <- seedProjectWithRootNode pool

        runSession
          ( do
              resp <-
                srequest $
                  putStatusRequest
                    (fromSqlKey rootKey)
                    (fromSqlKey projectKey)
                    "closed"
              assertStatus 200 resp
          )
          (handlePutNodeStatus pool)

        closedStatus <-
          flip runSqlPool pool $
            selectList [M.NodeStatusNodeStatusId ==. "closed"] []
        updated <- flip runSqlPool pool $ get rootKey
        case (closedStatus, updated) of
          ([Entity closedKey _], Just nd) ->
            M.nodeNodeStatusId nd `shouldBe` closedKey
          (_, Nothing) -> expectationFailure "expected the root Node to still exist"
          _ -> expectationFailure "expected the seeded \"closed\" status to exist"

      it "tells the header indicator the save landed, out of band" $ \pool -> do
        (projectKey, rootKey) <- seedProjectWithRootNode pool

        body <-
          runSession
            ( do
                resp <-
                  srequest $
                    putStatusRequest
                      (fromSqlKey rootKey)
                      (fromSqlKey projectKey)
                      "closed"
                assertStatus 200 resp
                pure . LC8.unpack . simpleBody $ resp
            )
            (handlePutNodeStatus pool)

        -- Status is the one field saved on `change` rather than after
        -- a typing delay, so it is the quickest way to see the header
        -- indicator settle -- and the easiest to forget to wire up.
        body `shouldSatisfy` isInfixOf "id=\"save-state-result\""
        body `shouldSatisfy` isInfixOf "hx-swap-oob=\"true\""
        body `shouldSatisfy` isInfixOf "save-state-saved"

      it "returns 404 when the node doesn't exist" $ \pool ->
        runSession
          ( do
              resp <- srequest $ putStatusRequest 999999 999999 "active"
              assertStatus 404 resp
          )
          (handlePutNodeStatus pool)

putStatusRequest :: Int64 -> Int64 -> LC8.ByteString -> SRequest
putStatusRequest nodeId projectId status =
  SRequest
    { simpleRequest =
        defaultRequest
          { requestMethod = methodPut
          , requestHeaders = [(hContentType, "application/x-www-form-urlencoded")]
          }
    , simpleRequestBody =
        "status="
          <> status
          <> "&nodeId="
          <> LC8.pack (show nodeId)
          <> "&projectId="
          <> LC8.pack (show projectId)
    }
