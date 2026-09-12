{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for 'handlePostWork', the UI-facing insert
behind the "Add work" panel.

The interesting half is the response rather than the row: this handler
has to close the panel that submitted it, open the new node's own
panel, and tell the graph to redraw, all from one response, and every
one of those is a header or a fragment the browser is relied upon to
act on.
-}
module Domain.Project.Responder.Ui.ProjectManage.Node.CreateSpec (spec) where

import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.Int (Int64)
import Data.List (isInfixOf)
import Database.Persist (Entity (..), selectList, (==.))
import Database.Persist.Sql (fromSqlKey, runSqlPool)
import qualified Domain.Project.Model as M
import Domain.Project.Responder.Ui.ProjectManage.Node.Create (handlePostWork)
import Integration.Support
  ( resetBetweenTests
  , seedProjectWithRootNode
  , withTestDatabase
  )
import Network.HTTP.Types (hContentType, methodPost)
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
    describe "handlePostWork (integration)" $ do
      it "inserts a work node on the project, active and undescribed" $ \pool -> do
        (projectKey, _) <- seedProjectWithRootNode pool

        runSession
          ( do
              resp <-
                srequest $
                  postWorkRequest (fromSqlKey projectKey) "Ship the thing"
              assertStatus 200 resp
          )
          (handlePostWork pool)

        created <-
          flip runSqlPool pool $
            selectList [M.NodeTitle ==. "Ship the thing"] []
        case created of
          [Entity _ nd] -> do
            M.nodeProjectId nd `shouldBe` projectKey
            M.unNodeTypeKey (M.nodeNodeTypeId nd) `shouldBe` "work"
            M.unNodeStatusKey (M.nodeNodeStatusId nd) `shouldBe` "active"
            -- The panel asks for a title and nothing else; a
            -- description is added afterwards, in the node's own panel.
            M.nodeDescription nd `shouldBe` ""
          _ -> expectationFailure "expected exactly one node with that title"

      it "answers with the new node's panel, swapped out of band" $ \pool -> do
        (projectKey, _) <- seedProjectWithRootNode pool

        body <-
          runSession
            ( do
                resp <-
                  srequest $
                    postWorkRequest (fromSqlKey projectKey) "Ship the thing"
                pure . LC8.unpack . simpleBody $ resp
            )
            (handlePostWork pool)

        -- Out of band because the response's own target is the panel
        -- that submitted it: that one is emptied (closing it), and the
        -- node panel is swapped by id instead.
        body `shouldSatisfy` isInfixOf "id=\"node-panel\""
        body `shouldSatisfy` isInfixOf "hx-swap-oob=\"innerHTML\""
        body `shouldSatisfy` isInfixOf "node-detail"

      -- The drawing is server-rendered, so a new node does not appear
      -- in it until the graph fragment is fetched again. This header is
      -- the only thing that makes that happen.
      it "triggers the graph to redraw" $ \pool -> do
        (projectKey, _) <- seedProjectWithRootNode pool

        headers <-
          runSession
            ( do
                resp <-
                  srequest $
                    postWorkRequest (fromSqlKey projectKey) "Ship the thing"
                pure . simpleHeaders $ resp
            )
            (handlePostWork pool)

        lookup "HX-Trigger" headers `shouldBe` Just "nodeCreated"

      it "rejects an empty title with 422, and says so in the panel" $ \pool -> do
        (projectKey, _) <- seedProjectWithRootNode pool

        body <-
          runSession
            ( do
                resp <- srequest $ postWorkRequest (fromSqlKey projectKey) ""
                assertStatus 422 resp
                pure . LC8.unpack . simpleBody $ resp
            )
            (handlePostWork pool)

        -- The form comes back rather than an error page: its target is
        -- the panel it lives in, so whatever is returned is what the
        -- person is left looking at.
        body `shouldSatisfy` isInfixOf "add-work-form"
        body `shouldSatisfy` isInfixOf "Title cannot be empty"

        nodes <-
          flip runSqlPool pool $ selectList [M.NodeTitle ==. ""] []
        length (nodes :: [Entity M.Node]) `shouldBe` 0

      -- A title of nothing but spaces is an empty title, and would
      -- otherwise draw a node with an invisible label.
      it "rejects a title that is only whitespace" $ \pool -> do
        (projectKey, _) <- seedProjectWithRootNode pool

        runSession
          ( do
              resp <- srequest $ postWorkRequest (fromSqlKey projectKey) "   "
              assertStatus 422 resp
          )
          (handlePostWork pool)

      it "rejects a project that does not exist" $ \pool ->
        runSession
          ( do
              resp <- srequest $ postWorkRequest 999999 "Ship the thing"
              assertStatus 422 resp
          )
          (handlePostWork pool)

postWorkRequest :: Int64 -> LC8.ByteString -> SRequest
postWorkRequest projectId title =
  SRequest
    { simpleRequest =
        defaultRequest
          { requestMethod = methodPost
          , requestHeaders = [(hContentType, "application/x-www-form-urlencoded")]
          }
    , simpleRequestBody =
        "title="
          <> urlTitle
          <> "&projectId="
          <> LC8.pack (show projectId)
    }
  where
    -- Spaces have to reach the handler as a form encoding, not as raw
    -- spaces, or the body is a different request than the browser's.
    urlTitle = LC8.map (\c -> if c == ' ' then '+' else c) title
