{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for @GET /ui/project/stats@.

The arithmetic is covered as a pure function in
@Domain.Project.StatsSpec@; what needs a real database is the pair of
queries feeding it -- that the status vocabulary comes back in full, and
that the counts are the project's own work nodes rather than every row
in the table.
-}
module Domain.Project.Responder.Ui.ProjectManage.StatsSpec (spec) where

import Data.Int (Int64)
import Data.Text (Text, pack)
import Database.Persist (Entity (..), selectList, update, (=.), (==.))
import Database.Persist.Sql (Key, fromSqlKey, runSqlPool)
import qualified Domain.Project.Model as M
import Integration.Support
  ( TestApp (..)
  , bodyOf
  , httpGet
  , resetBetweenTests
  , seedProjectWithRootNode
  , seedWorkNode
  , shouldContainStr
  , statusOf
  , withTestApp
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestApp $
  beforeWith resetBetweenTests $
    describe "GET /ui/project/stats (integration)" $ do
      it "counts the project's work nodes" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta
        _ <- seedWorkNode ta projectKey "Build the thing"
        _ <- seedWorkNode ta projectKey "Ship the thing"

        body <- statsBody ta (fromSqlKey projectKey)

        body `shouldContainStr` statRow "Total nodes" "2"

      -- The root node is a structural row, not work: the drawing leaves
      -- it out, so a count of "nodes" that included it would disagree
      -- with what the user is looking at.
      it "leaves the project's root node out of the count" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta

        body <- statsBody ta (fromSqlKey projectKey)

        body `shouldContainStr` statRow "Total nodes" "0"

      it "counts only the project asked about" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta
        _ <- seedWorkNode ta projectKey "Ours"
        (otherKey, _) <- seedProjectWithRootNode ta
        _ <- seedWorkNode ta otherKey "Someone else's"
        _ <- seedWorkNode ta otherKey "Also not ours"

        body <- statsBody ta (fromSqlKey projectKey)

        body `shouldContainStr` statRow "Total nodes" "1"

      -- A status nothing is sitting in still gets a row, because the
      -- vocabulary comes from the status table rather than from the
      -- rows that happen to exist.
      it "gives every status in the table a row of its own" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta
        _ <- seedWorkNode ta projectKey "Build the thing"

        body <- statsBody ta (fromSqlKey projectKey)

        body `shouldContainStr` statRow "Active" "1"
        body `shouldContainStr` statRow "Closed" "0"
        body `shouldContainStr` statRow "Open" "0"
        body `shouldContainStr` statRow "Rejected" "0"

      it "reports completion as the closed share of the work" $ \ta -> do
        (projectKey, _) <- seedProjectWithRootNode ta
        done <- seedWorkNode ta projectKey "Finished"
        _ <- seedWorkNode ta projectKey "Still going"
        _ <- seedWorkNode ta projectKey "Not started"
        _ <- seedWorkNode ta projectKey "Also going"
        closeNode ta done

        body <- statsBody ta (fromSqlKey projectKey)

        body `shouldContainStr` statRow "Completion" "25%"

      it "answers a missing project id with a 400 rather than a 500" $ \ta -> do
        resp <- httpGet ta "/ui/project/stats"
        statusOf resp `shouldBe` 400

statsBody :: TestApp -> Int64 -> IO String
statsBody ta pid = do
  resp <- httpGet ta (statsUrl pid)
  statusOf resp `shouldBe` 200
  pure (bodyOf resp)

statsUrl :: Int64 -> Text
statsUrl pid = "/ui/project/stats?projectId=" <> pack (show pid)

closeNode :: TestApp -> Key M.Node -> IO ()
closeNode ta nodeKey = flip runSqlPool (testPool ta) $ do
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
