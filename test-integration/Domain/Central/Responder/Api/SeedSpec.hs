{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for what the app's own seed step puts in the
database: the reference rows @project.node@ points at, and nothing
else.

The second half is the interesting half. Fixture data belongs in
@local\/sql\/demo-data.sql@, applied against the database with the app
uninvolved, so a seed that started inserting projects or nodes would
be a boundary being crossed rather than a harmless extra — and that
is cheap to pin here.
-}
module Domain.Central.Responder.Api.SeedSpec (spec) where

import Data.List (sort)
import Database.Persist (Entity, selectList)
import Database.Persist.Sql (ConnectionPool, entityVal, runSqlPool)
import Domain.Central.Responder.Api.Seed
  ( nodeStatuses
  , nodeTypes
  , seedReferenceData
  )
import qualified Domain.Project.Model as M
import Integration.Support (resetBetweenTests, withTestDatabase)
import Test.Hspec

seed :: ConnectionPool -> IO ()
seed = runSqlPool seedReferenceData

statusIds :: ConnectionPool -> IO [String]
statusIds pool =
  map (M.nodeStatusNodeStatusId . entityVal)
    <$> runSqlPool (selectList [] []) pool

typeIds :: ConnectionPool -> IO [String]
typeIds pool =
  map (M.nodeTypeNodeTypeId . entityVal)
    <$> runSqlPool (selectList [] []) pool

nodeCount :: ConnectionPool -> IO Int
nodeCount pool = do
  rows <- runSqlPool (selectList [] []) pool
  pure (length (rows :: [Entity M.Node]))

projectCount :: ConnectionPool -> IO Int
projectCount pool = do
  rows <- runSqlPool (selectList [] []) pool
  pure (length (rows :: [Entity M.Project]))

spec :: Spec
spec =
  -- `aroundAll`, not `around`: one container for the whole spec, with
  -- `resetBetweenTests` truncating between examples. Every other spec
  -- in this suite does it this way.
  aroundAll withTestDatabase
    . beforeWith resetBetweenTests
    $ describe "seedReferenceData (integration)"
    $ do
      it "inserts every node status the app defines" $ \pool -> do
        seed pool
        ids <- statusIds pool
        sort ids `shouldBe` sort [s | M.NodeStatus s <- nodeStatuses]

      it "inserts every node type the app defines" $ \pool -> do
        seed pool
        ids <- typeIds pool
        sort ids `shouldBe` sort [t | M.NodeType t <- nodeTypes]

      -- The container is seeded once at startup, so every run of this
      -- lands on rows that are already there.
      it "is idempotent -- seeding twice leaves one row per value" $ \pool -> do
        seed pool
        seed pool
        statuses <- statusIds pool
        types <- typeIds pool
        length statuses `shouldBe` length nodeStatuses
        length types `shouldBe` length nodeTypes

      -- The boundary: fixture and demo data live outside the app, in
      -- local/sql/demo-data.sql.
      it "creates no projects or nodes of its own" $ \pool -> do
        seed pool
        projects <- projectCount pool
        nodes <- nodeCount pool
        projects `shouldBe` 0
        nodes `shouldBe` 0
