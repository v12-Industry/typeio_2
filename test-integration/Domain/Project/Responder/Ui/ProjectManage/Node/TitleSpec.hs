{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for 'handlePutTitle', building on the
infrastructure and pattern established in the pilot
('Domain.Project.Responder.Api.Node.PostSpec').
-}
module Domain.Project.Responder.Ui.ProjectManage.Node.TitleSpec (spec) where

import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.Int (Int64)
import Data.List (isInfixOf)
import Database.Persist (get)
import Database.Persist.Sql (fromSqlKey, runSqlPool)
import qualified Domain.Project.Model as M
import Domain.Project.Responder.Ui.ProjectManage.Node.Title (handlePutTitle)
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
    describe "handlePutTitle (integration)" $ do
      it "replaces the Node's title in the database" $ \pool -> do
        (projectKey, rootKey) <- seedProjectWithRootNode pool

        runSession
          ( do
              resp <-
                srequest $
                  putTitleRequest
                    (fromSqlKey rootKey)
                    (fromSqlKey projectKey)
                    "UpdatedTitle"
              assertStatus 200 resp
          )
          (handlePutTitle pool)

        updated <- flip runSqlPool pool $ get rootKey
        case updated of
          Just nd -> M.nodeTitle nd `shouldBe` "UpdatedTitle"
          Nothing -> expectationFailure "expected the root Node to still exist"

      it "tells the header indicator the save landed, out of band" $ \pool -> do
        (projectKey, rootKey) <- seedProjectWithRootNode pool

        body <-
          runSession
            ( do
                resp <-
                  srequest $
                    putTitleRequest
                      (fromSqlKey rootKey)
                      (fromSqlKey projectKey)
                      "UpdatedTitle"
                assertStatus 200 resp
                pure . LC8.unpack . simpleBody $ resp
            )
            (handlePutTitle pool)

        -- This response is swapped into the title field's own
        -- indicator box. The header's aggregate indicator sits outside
        -- that target and is reached only by the out-of-band fragment
        -- riding along with it, so both halves have to be present.
        body `shouldSatisfy` isInfixOf "id=\"save-state-result\""
        body `shouldSatisfy` isInfixOf "hx-swap-oob=\"true\""
        body `shouldSatisfy` isInfixOf "save-state-saved"

      it "returns 404 when the node doesn't exist" $ \pool ->
        runSession
          ( do
              resp <- srequest $ putTitleRequest 999999 999999 "title"
              assertStatus 404 resp
          )
          (handlePutTitle pool)

putTitleRequest :: Int64 -> Int64 -> LC8.ByteString -> SRequest
putTitleRequest nodeId projectId title =
  SRequest
    { simpleRequest =
        defaultRequest
          { requestMethod = methodPut
          , requestHeaders = [(hContentType, "application/x-www-form-urlencoded")]
          }
    , simpleRequestBody =
        "title="
          <> title
          <> "&nodeId="
          <> LC8.pack (show nodeId)
          <> "&projectId="
          <> LC8.pack (show projectId)
    }
