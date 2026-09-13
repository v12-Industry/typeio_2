{-# LANGUAGE OverloadedStrings #-}

{- | The pilot integration test from
@docs/solution-proposals/integration-testing.md@ §3/§11: exercises
@POST /api/project/nodes@ against a real, migrated, disposable
Postgres rather than a hand-built fake -- exactly the multi-table,
foreign-key-driven flow a unit test (with or without a repository
layer) can't meaningfully cover.
-}
module Domain.Project.Responder.Api.Node.PostSpec (spec) where

import qualified Data.ByteString.Char8 as C8
import Data.Int (Int64)
import Database.Persist (Entity (..), selectList, (==.))
import Database.Persist.Sql (fromSqlKey, runSqlPool)
import qualified Domain.Project.Model as M
import Integration.Support
  ( SResponse
  , TestApp (..)
  , formBody
  , headerOf
  , httpPost
  , resetBetweenTests
  , seedProjectWithRootNode
  , statusOf
  , withTestApp
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestApp $
  beforeWith resetBetweenTests $
    describe "POST /api/project/nodes (integration)" $ do
      it "inserts a new work Node into the project, with no dependency row" $ \ta -> do
        (projectKey, _rootKey) <- seedProjectWithRootNode ta

        resp <- postNode ta (fromSqlKey projectKey) "ANewNode" "NewNode"
        -- 201, not 200: the route is a PostCreated, and the Location
        -- header is the other half of that answer.
        statusOf resp `shouldBe` 201
        headerOf "Location" resp `shouldSatisfy` (/= Nothing)

        newNodes <-
          flip runSqlPool (testPool ta) $
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
              flip runSqlPool (testPool ta) $
                selectList [M.DependencyNodeId ==. newNodeKey] []
            length deps `shouldBe` 0
          other ->
            expectationFailure $
              "expected exactly one new Node titled \"NewNode\", got "
                <> show (length other)

      it "returns 404 when the project doesn't exist" $ \ta -> do
        resp <- postNode ta 999999 "desc" "title"
        statusOf resp `shouldBe` 404

      -- The payload is validated before a row is written, so a
      -- rejected one is the caller's 422 rather than a constraint
      -- violation surfacing as a 500.
      it "returns 422 for an empty description" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta
        resp <- postNode ta (fromSqlKey projectKey) "" "NewNode"
        statusOf resp `shouldBe` 422

postNode :: TestApp -> Int64 -> C8.ByteString -> C8.ByteString -> IO SResponse
postNode ta projectId descr title =
  httpPost
    ta
    "/api/project/nodes"
    ( formBody
        [ ("description", descr)
        , ("title", title)
        , ("projectId", C8.pack (show projectId))
        ]
    )
