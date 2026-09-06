{-# LANGUAGE OverloadedStrings #-}

{- | The pilot integration test from
@docs/solution-proposals/integration-testing.md@ §3/§11: exercises
'handlePostNode' against a real, migrated, disposable Postgres
rather than a hand-built fake -- exactly the multi-table,
foreign-key-driven flow a unit test (with or without a repository
layer) can't meaningfully cover.
-}
module Domain.Project.Responder.Api.Node.PostSpec (spec) where

import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.Int (Int64)
import Database.Persist (Entity (..), selectList, (==.))
import Database.Persist.Sql (fromSqlKey, runSqlPool)
import qualified Domain.Project.Model as M
import Domain.Project.Responder.Api.Node.Post (handlePostNode)
import Integration.Support
  ( resetBetweenTests
  , seedProjectWithRootNode
  , withTestDatabase
  )
import Network.HTTP.Types (hContentType, methodPost)
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
    describe "handlePostNode (integration)" $ do
      it "inserts a new work Node into the project, with no dependency row" $ \pool -> do
        (projectKey, _rootKey) <- seedProjectWithRootNode pool

        runSession
          ( do
              resp <- srequest $ postNodeRequest (fromSqlKey projectKey) "ANewNode" "NewNode"
              assertStatus 200 resp
          )
          (handlePostNode pool)

        newNodes <-
          flip runSqlPool pool $
            selectList [M.NodeTitle ==. "NewNode"] []
        case newNodes of
          [Entity newNodeKey newNode] -> do
            M.nodeDescription newNode `shouldBe` "ANewNode"
            M.nodeProjectId newNode `shouldBe` projectKey

            -- No dependency row. One pointing at the project root
            -- would record membership -- but `node.project_id`,
            -- asserted just above, already records exactly that.
            -- Storing it twice puts the root at the bottom of the
            -- graph, because a `project.dependency` row means an
            -- ordering between two pieces of work and layout draws it as
            -- one.
            deps <-
              flip runSqlPool pool $
                selectList [M.DependencyNodeId ==. newNodeKey] []
            length deps `shouldBe` 0
          other ->
            expectationFailure $
              "expected exactly one new Node titled \"NewNode\", got "
                <> show (length other)

      it "returns 404 when the project doesn't exist" $ \pool ->
        runSession
          ( do
              resp <- srequest $ postNodeRequest 999999 "desc" "title"
              assertStatus 404 resp
          )
          (handlePostNode pool)

{- | Builds a form-encoded @handlePostNode@ request the same way a real
client would submit it (@application/x-www-form-urlencoded@, per
'Domain.Project.Responder.Api.Node.Post.paramToPayload').
-}
postNodeRequest :: Int64 -> LC8.ByteString -> LC8.ByteString -> SRequest
postNodeRequest projectId descr title =
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
          <> "&projectId="
          <> LC8.pack (show projectId)
    }
