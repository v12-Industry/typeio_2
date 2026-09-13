{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for @PUT /ui/project/node/status@, building on
the infrastructure and pattern established in the pilot
('Domain.Project.Responder.Api.Node.PostSpec').
-}
module Domain.Project.Responder.Ui.ProjectManage.Node.StatusSpec (spec) where

import qualified Data.ByteString.Char8 as C8
import Data.Int (Int64)
import Database.Persist (Entity (..), get, selectList, (==.))
import Database.Persist.Sql (fromSqlKey, runSqlPool)
import qualified Domain.Project.Model as M
import Integration.Support
  ( SResponse
  , TestApp (..)
  , bodyOf
  , formBody
  , httpPut
  , resetBetweenTests
  , seedProjectWithRootNode
  , shouldContainStr
  , statusOf
  , withTestApp
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestApp $
  beforeWith resetBetweenTests $
    describe "PUT /ui/project/node/status (integration)" $ do
      it "replaces the Node's status in the database" $ \ta -> do
        (projectKey, rootKey) <- seedProjectWithRootNode ta

        resp <- putStatus ta (fromSqlKey rootKey) (fromSqlKey projectKey) "closed"
        statusOf resp `shouldBe` 200

        closedStatus <-
          flip runSqlPool (testPool ta) $
            selectList [M.NodeStatusNodeStatusId ==. "closed"] []
        updated <- flip runSqlPool (testPool ta) $ get rootKey
        case (closedStatus, updated) of
          ([Entity closedKey _], Just nd) ->
            M.nodeNodeStatusId nd `shouldBe` closedKey
          (_, Nothing) -> expectationFailure "expected the root Node to still exist"
          _ -> expectationFailure "expected the seeded \"closed\" status to exist"

      it "rejects an empty status with 422 rather than a 500" $ \ta -> do
        (projectKey, rootKey) <- seedProjectWithRootNode ta

        resp <- putStatus ta (fromSqlKey rootKey) (fromSqlKey projectKey) ""
        statusOf resp `shouldBe` 422

        -- Same reasoning as the other two fields: a rejected value
        -- is a 422, and 5xx would not be swapped into the field at
        -- all.
        bodyOf resp `shouldContainStr` "material-icons"

      it "returns 404 when the node doesn't exist" $ \ta -> do
        resp <- putStatus ta 999999 999999 "active"
        statusOf resp `shouldBe` 404

putStatus :: TestApp -> Int64 -> Int64 -> C8.ByteString -> IO SResponse
putStatus ta nodeId projectId status =
  httpPut
    ta
    "/ui/project/node/status"
    ( formBody
        [ ("status", status)
        , ("nodeId", C8.pack (show nodeId))
        , ("projectId", C8.pack (show projectId))
        ]
    )
