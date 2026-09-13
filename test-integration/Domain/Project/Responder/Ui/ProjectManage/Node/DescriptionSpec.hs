{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for @PUT /ui/project/node/description@,
building on the infrastructure and pattern established in the pilot
('Domain.Project.Responder.Api.Node.PostSpec').
-}
module Domain.Project.Responder.Ui.ProjectManage.Node.DescriptionSpec (spec) where

import qualified Data.ByteString.Char8 as C8
import Data.Int (Int64)
import Database.Persist (get)
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
    describe "PUT /ui/project/node/description (integration)" $ do
      it "replaces the Node's description in the database" $ \ta -> do
        (projectKey, rootKey) <- seedProjectWithRootNode ta

        resp <-
          putDescription
            ta
            (fromSqlKey rootKey)
            (fromSqlKey projectKey)
            "UpdatedDescription"
        statusOf resp `shouldBe` 200

        updated <- flip runSqlPool (testPool ta) $ get rootKey
        case updated of
          Just nd -> M.nodeDescription nd `shouldBe` "UpdatedDescription"
          Nothing -> expectationFailure "expected the root Node to still exist"

      it "rejects an empty description with 422 rather than a 500" $ \ta -> do
        (projectKey, rootKey) <- seedProjectWithRootNode ta

        resp <- putDescription ta (fromSqlKey rootKey) (fromSqlKey projectKey) ""
        statusOf resp `shouldBe` 422

        -- A validation failure is the caller's, not the server's.
        -- It also has to be swappable: htmx does not swap 5xx at
        -- all, so under a 500 these messages were rendered and then
        -- dropped on the floor, and the field showed nothing.
        bodyOf resp `shouldContainStr` "Node description cannot be empty"

      it "returns 404 when the node doesn't exist" $ \ta -> do
        resp <- putDescription ta 999999 999999 "desc"
        statusOf resp `shouldBe` 404

putDescription :: TestApp -> Int64 -> Int64 -> C8.ByteString -> IO SResponse
putDescription ta nodeId projectId descr =
  httpPut
    ta
    "/ui/project/node/description"
    ( formBody
        [ ("description", descr)
        , ("nodeId", C8.pack (show nodeId))
        , ("projectId", C8.pack (show projectId))
        ]
    )
