{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for 'handleGetProjectStats'.

The arithmetic is covered as a pure function in
@Domain.Project.StatsSpec@; what needs a real database is the pair of
queries feeding it -- that the status vocabulary comes back in full, and
that the counts are the project's own work nodes rather than every row
in the table.
-}
module Domain.Project.Responder.Ui.ProjectManage.StatsSpec (spec) where

import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.Int (Int64)
import Data.List (isInfixOf)
import Database.Persist (Entity (..), selectList, update, (=.), (==.))
import Database.Persist.Sql (ConnectionPool, Key, fromSqlKey, runSqlPool)
import qualified Domain.Project.Model as M
import Domain.Project.Responder.Ui.ProjectManage.Stats (handleGetProjectStats)
import Integration.Support
  ( resetBetweenTests
  , seedProjectWithRootNode
  , seedWorkNode
  , withTestDatabase
  )
import Network.HTTP.Types (methodGet)
import Network.Wai (Request, defaultRequest, queryString, requestMethod)
import Network.Wai.Test
  ( SResponse (..)
  , request
  , runSession
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestDatabase $
  beforeWith resetBetweenTests $
    describe "handleGetProjectStats (integration)" $ do
      it "counts the project's work nodes" $ \pool -> do
        (projectKey, _) <- seedProjectWithRootNode pool
        _ <- seedWorkNode pool projectKey "Build the thing"
        _ <- seedWorkNode pool projectKey "Ship the thing"

        body <- statsBody pool (fromSqlKey projectKey)

        body `shouldContainStr` statRow "Total nodes" "2"

      -- The root node is a structural row, not work: the drawing leaves
      -- it out, so a count of "nodes" that included it would disagree
      -- with what the user is looking at.
      it "leaves the project's root node out of the count" $ \pool -> do
        (projectKey, _) <- seedProjectWithRootNode pool

        body <- statsBody pool (fromSqlKey projectKey)

        body `shouldContainStr` statRow "Total nodes" "0"

      it "counts only the project asked about" $ \pool -> do
        (projectKey, _) <- seedProjectWithRootNode pool
        _ <- seedWorkNode pool projectKey "Ours"
        (otherKey, _) <- seedProjectWithRootNode pool
        _ <- seedWorkNode pool otherKey "Someone else's"
        _ <- seedWorkNode pool otherKey "Also not ours"

        body <- statsBody pool (fromSqlKey projectKey)

        body `shouldContainStr` statRow "Total nodes" "1"

      -- A status nothing is sitting in still gets a row, because the
      -- vocabulary comes from the status table rather than from the
      -- rows that happen to exist.
      it "gives every status in the table a row of its own" $ \pool -> do
        (projectKey, _) <- seedProjectWithRootNode pool
        _ <- seedWorkNode pool projectKey "Build the thing"

        body <- statsBody pool (fromSqlKey projectKey)

        body `shouldContainStr` statRow "Active" "1"
        body `shouldContainStr` statRow "Closed" "0"
        body `shouldContainStr` statRow "Open" "0"
        body `shouldContainStr` statRow "Rejected" "0"

      it "reports completion as the closed share of the work" $ \pool -> do
        (projectKey, _) <- seedProjectWithRootNode pool
        done <- seedWorkNode pool projectKey "Finished"
        _ <- seedWorkNode pool projectKey "Still going"
        _ <- seedWorkNode pool projectKey "Not started"
        _ <- seedWorkNode pool projectKey "Also going"
        closeNode pool done

        body <- statsBody pool (fromSqlKey projectKey)

        body `shouldContainStr` statRow "Completion" "25%"

      it "answers a missing project id with a 400 rather than a 500" $ \pool -> do
        status <-
          runSession
            (simpleStatus <$> request (statsRequest []))
            (handleGetProjectStats pool)

        show status `shouldContain` "400"

statsBody :: ConnectionPool -> Int64 -> IO String
statsBody pool pid =
  runSession
    ( LC8.unpack . simpleBody
        <$> request (statsRequest [("projectId", Just (C8.pack (show pid)))])
    )
    (handleGetProjectStats pool)

statsRequest :: [(C8.ByteString, Maybe C8.ByteString)] -> Request
statsRequest qs =
  defaultRequest
    { requestMethod = methodGet
    , queryString = qs
    }

closeNode :: ConnectionPool -> Key M.Node -> IO ()
closeNode pool nodeKey = flip runSqlPool pool $ do
  closed <- selectList [M.NodeStatusNodeStatusId ==. "closed"] []
  case closed of
    (Entity closedKey _ : _) -> update nodeKey [M.NodeNodeStatusId =. closedKey]
    [] -> pure ()

statRow :: String -> String -> String
statRow label value =
  "<span class=\"stat-label\">"
    <> label
    <> "</span><span class=\"stat-value\">"
    <> value
    <> "</span>"

shouldContainStr :: String -> String -> Expectation
shouldContainStr haystack needle =
  (needle `isInfixOf` haystack) `shouldBe` True
