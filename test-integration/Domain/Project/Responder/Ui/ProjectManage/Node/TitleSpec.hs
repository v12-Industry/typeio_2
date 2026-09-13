{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for @PUT /ui/project/node/title@, building on
the infrastructure and pattern established in the pilot
('Domain.Project.Responder.Api.Node.PostSpec').
-}
module Domain.Project.Responder.Ui.ProjectManage.Node.TitleSpec (spec) where

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
    describe "PUT /ui/project/node/title (integration)" $ do
      it "replaces the Node's title in the database" $ \ta -> do
        (projectKey, rootKey) <- seedProjectWithRootNode ta

        resp <- putTitle ta (fromSqlKey rootKey) (fromSqlKey projectKey) "UpdatedTitle"
        statusOf resp `shouldBe` 200

        updated <- flip runSqlPool (testPool ta) $ get rootKey
        case updated of
          Just nd -> M.nodeTitle nd `shouldBe` "UpdatedTitle"
          Nothing -> expectationFailure "expected the root Node to still exist"

      it "rejects an empty title with 422 rather than a 200 that looks saved" $ \ta -> do
        (projectKey, rootKey) <- seedProjectWithRootNode ta

        resp <- putTitle ta (fromSqlKey rootKey) (fromSqlKey projectKey) ""
        statusOf resp `shouldBe` 422

        -- The status code is the whole mechanism now: the header
        -- indicator tells a failed save from a good one by asking
        -- htmx whether the response was successful, and a 200
        -- carrying an error message reads as a success. The app's
        -- htmx-config keeps 422 swappable, so the field's own error
        -- markup still reaches the page.
        bodyOf resp `shouldContainStr` "Node title cannot be empty"

      it "returns 404 when the node doesn't exist" $ \ta -> do
        resp <- putTitle ta 999999 999999 "title"
        statusOf resp `shouldBe` 404

putTitle :: TestApp -> Int64 -> Int64 -> C8.ByteString -> IO SResponse
putTitle ta nodeId projectId title =
  httpPut
    ta
    "/ui/project/node/title"
    ( formBody
        [ ("title", title)
        , ("nodeId", C8.pack (show nodeId))
        , ("projectId", C8.pack (show projectId))
        ]
    )
