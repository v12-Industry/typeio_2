{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for the "Add work" panel's two routes,
@GET@ and @POST /ui/project/node/create@.

The interesting half of the POST is the response rather than the row:
it has to close the panel that submitted it, open the new node's own
panel, and tell the graph to redraw, all from one response, and every
one of those is a header or a fragment the browser is relied upon to
act on.
-}
module Domain.Project.Responder.Ui.ProjectManage.Node.CreateSpec (spec) where

import qualified Data.ByteString.Char8 as C8
import Data.Int (Int64)
import Data.Text (Text, pack)
import Database.Persist (Entity (..), selectList, (==.))
import Database.Persist.Sql (fromSqlKey, runSqlPool)
import qualified Domain.Project.Model as M
import Integration.Support
  ( SResponse
  , TestApp (..)
  , bodyOf
  , formBody
  , headerOf
  , httpGet
  , httpPost
  , resetBetweenTests
  , seedProjectWithRootNode
  , shouldContainStr
  , statusOf
  , withTestApp
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestApp $
  beforeWith resetBetweenTests $ do
    describe "GET /ui/project/node/create (integration)" $ do
      it "renders the form for the project asked about" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta

        resp <- httpGet ta (createUrl (fromSqlKey projectKey))
        statusOf resp `shouldBe` 200
        bodyOf resp `shouldContainStr` "add-work-form"
        bodyOf resp
          `shouldContainStr` ( "name=\"projectId\" value=\""
                                 <> show (fromSqlKey projectKey)
                                 <> "\""
                             )

      -- The parameter is Strict, so a missing or malformed one is
      -- refused before the template is ever built. Both are statuses
      -- htmx declines to swap, so the panel is left as it was.
      it "refuses a missing project id" $ \ta -> do
        resp <- httpGet ta "/ui/project/node/create"
        statusOf resp `shouldBe` 400

      it "refuses a project id that is not a number" $ \ta -> do
        resp <- httpGet ta "/ui/project/node/create?projectId=one"
        statusOf resp `shouldBe` 400

    describe "POST /ui/project/node/create (integration)" $ do
      it "inserts a work node on the project, active and undescribed" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta

        resp <- postWork ta (fromSqlKey projectKey) "Ship the thing"
        statusOf resp `shouldBe` 200

        created <-
          flip runSqlPool (testPool ta) $
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

      it "answers with the new node's panel, swapped out of band" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta

        resp <- postWork ta (fromSqlKey projectKey) "Ship the thing"

        -- Out of band because the response's own target is the panel
        -- that submitted it: that one is emptied (closing it), and the
        -- node panel is swapped by id instead.
        bodyOf resp `shouldContainStr` "id=\"node-panel\""
        bodyOf resp `shouldContainStr` "hx-swap-oob=\"innerHTML\""
        bodyOf resp `shouldContainStr` "node-detail"

      -- The drawing is server-rendered, so a new node does not appear
      -- in it until the graph fragment is fetched again. This header is
      -- the only thing that makes that happen.
      it "triggers the graph to redraw" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta

        resp <- postWork ta (fromSqlKey projectKey) "Ship the thing"

        headerOf "HX-Trigger" resp `shouldBe` Just "nodeCreated"

      it "rejects an empty title with 422, and says so in the panel" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta

        resp <- postWork ta (fromSqlKey projectKey) ""
        statusOf resp `shouldBe` 422

        -- The form comes back rather than an error page: its target is
        -- the panel it lives in, so whatever is returned is what the
        -- person is left looking at.
        bodyOf resp `shouldContainStr` "add-work-form"
        bodyOf resp `shouldContainStr` "Title cannot be empty"

        nodes <-
          flip runSqlPool (testPool ta) $ selectList [M.NodeTitle ==. ""] []
        length (nodes :: [Entity M.Node]) `shouldBe` 0

      -- A title of nothing but spaces is an empty title, and would
      -- otherwise draw a node with an invisible label.
      it "rejects a title that is only whitespace" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta

        resp <- postWork ta (fromSqlKey projectKey) "   "
        statusOf resp `shouldBe` 422

      it "rejects a project that does not exist" $ \ta -> do
        resp <- postWork ta 999999 "Ship the thing"
        statusOf resp `shouldBe` 422

createUrl :: Int64 -> Text
createUrl pid = "/ui/project/node/create?projectId=" <> pack (show pid)

postWork :: TestApp -> Int64 -> C8.ByteString -> IO SResponse
postWork ta projectId title =
  httpPost
    ta
    "/ui/project/node/create"
    (formBody [("title", title), ("projectId", C8.pack (show projectId))])
