{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for what the app's own seed step puts in the
database: the reference rows @project.node@ points at, and nothing
else.

Driven through @POST /api/central/seed-database@, the endpoint
@make seed-db@ calls, rather than by calling the seeding function --
so what is pinned includes the route being wired to it.

The second half is the interesting half. Fixture data belongs in
@local\/sql\/demo-data.sql@, applied against the database with the app
uninvolved, so a seed that started inserting projects or nodes would
be a boundary being crossed rather than a harmless extra -- and that
is cheap to pin here.
-}
module Domain.Central.Responder.Api.SeedSpec (spec) where

import Data.List (sort)
import Database.Persist (Entity, selectList)
import Database.Persist.Sql (entityVal, runSqlPool)
import Domain.Central.Responder.Api.Seed (nodeStatuses, nodeTypes)
import qualified Domain.Project.Model as M
import Integration.Support
  ( TestApp (..)
  , formBody
  , httpPost
  , resetBetweenTests
  , statusOf
  , withTestApp
  )
import Test.Hspec

seed :: TestApp -> IO ()
seed ta = do
  resp <- httpPost ta "/api/central/seed-database" (formBody [])
  statusOf resp `shouldBe` 200

statusIds :: TestApp -> IO [String]
statusIds ta =
  map (M.nodeStatusNodeStatusId . entityVal)
    <$> runSqlPool (selectList [] []) (testPool ta)

typeIds :: TestApp -> IO [String]
typeIds ta =
  map (M.nodeTypeNodeTypeId . entityVal)
    <$> runSqlPool (selectList [] []) (testPool ta)

nodeCount :: TestApp -> IO Int
nodeCount ta = do
  rows <- runSqlPool (selectList [] []) (testPool ta)
  pure (length (rows :: [Entity M.Node]))

projectCount :: TestApp -> IO Int
projectCount ta = do
  rows <- runSqlPool (selectList [] []) (testPool ta)
  pure (length (rows :: [Entity M.Project]))

spec :: Spec
spec =
  -- `aroundAll`, not `around`: one container for the whole spec, with
  -- `resetBetweenTests` truncating between examples. Every other spec
  -- in this suite does it this way.
  aroundAll withTestApp
    . beforeWith resetBetweenTests
    $ describe "POST /api/central/seed-database (integration)"
    $ do
      it "inserts every node status the app defines" $ \ta -> do
        seed ta
        ids <- statusIds ta
        sort ids `shouldBe` sort [s | M.NodeStatus s <- nodeStatuses]

      it "inserts every node type the app defines" $ \ta -> do
        seed ta
        ids <- typeIds ta
        sort ids `shouldBe` sort [t | M.NodeType t <- nodeTypes]

      -- The container is seeded once at startup, so every run of this
      -- lands on rows that are already there.
      it "is idempotent -- seeding twice leaves one row per value" $ \ta -> do
        seed ta
        seed ta
        statuses <- statusIds ta
        types <- typeIds ta
        length statuses `shouldBe` length nodeStatuses
        length types `shouldBe` length nodeTypes

      -- The boundary: fixture and demo data live outside the app, in
      -- local/sql/demo-data.sql.
      it "creates no projects or nodes of its own" $ \ta -> do
        seed ta
        projects <- projectCount ta
        nodes <- nodeCount ta
        projects `shouldBe` 0
        nodes `shouldBe` 0
