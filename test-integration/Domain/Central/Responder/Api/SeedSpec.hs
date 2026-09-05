{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for the demo project the seed inserts (#243).

Worth pinning rather than eyeballing, because the thing that makes this
fixture useful is its /shape/, not its size. Before it existed no
project had a single dependency — @Api.Node.Post@ was the only writer of
@project.dependency@ and #198 removed the rows it wrote — so every graph
in the app was a set of disconnected nodes and every visualization
looked much the same.

The assertions here are the properties the later orbital issues depend
on: a shared bottleneck (so a node is replicated at all), a replicated
subtree beneath it, more than one head, and idempotency, since this runs
against a database somebody may already have seeded.
-}
module Domain.Central.Responder.Api.SeedSpec (spec) where

import Data.List (group, nub, sort)
import Database.Persist (Entity, selectList)
import Database.Persist.Sql (ConnectionPool, entityVal, runSqlPool)
import Domain.Central.Responder.Api.Seed
  ( demoDependencies
  , demoRootTitle
  , demoWork
  , seedDemoProject
  )
import qualified Domain.Project.Model as M
import Integration.Support (resetBetweenTests, withTestDatabase)
import Test.Hspec

seed :: ConnectionPool -> IO ()
seed = runSqlPool seedDemoProject

nodeTitles :: ConnectionPool -> IO [String]
nodeTitles pool =
  map (M.nodeTitle . entityVal) <$> runSqlPool (selectList [] []) pool

dependencyPairs :: ConnectionPool -> IO [(M.NodeId, M.NodeId)]
dependencyPairs pool =
  map (pair . entityVal) <$> runSqlPool (selectList [] []) pool
  where
    pair d = (M.dependencyNodeId d, M.dependencyToNodeId d)

{- | The dependency rows grouped by what is being waited on, so each
group's length is how many dependents that node has — which is exactly
how many times the orbital drawing replicates it.
-}
dependentGroups :: [(M.NodeId, M.NodeId)] -> [[M.NodeId]]
dependentGroups ds = group (sort [dependency | (_, dependency) <- ds])

projectCount :: ConnectionPool -> IO Int
projectCount pool = do
  rows <- runSqlPool (selectList [] []) pool
  pure (length (rows :: [Entity M.Project]))

spec :: Spec
spec =
  -- `aroundAll`, not `around`: one container for the whole spec, with
  -- `resetBetweenTests` truncating between examples. `around` starts a
  -- fresh Postgres per example, which is how this suite went from ~45
  -- seconds to nine minutes and began failing with "Bad response from
  -- Docker engine" once enough containers were in flight. Every other
  -- spec here already does it this way; this one was the outlier
  -- (introduced in #243, found in #244).
  aroundAll withTestDatabase
    . beforeWith resetBetweenTests
    $ describe "seedDemoProject (integration)"
    $ do
      it "inserts the root node and every work node" $ \pool -> do
        seed pool
        titles <- nodeTitles pool
        sort titles
          `shouldBe` sort (demoRootTitle : [t | (_, t, _) <- demoWork])

      it "records every dependency" $ \pool -> do
        seed pool
        ds <- dependencyPairs pool
        length ds `shouldBe` length demoDependencies

      it "gives some node more than one dependent, so a drawing can replicate it" $ \pool -> do
        -- The whole point of the fixture. A node is replicated in the
        -- orbital drawing once per dependent, so without this the
        -- visualization has nothing to demonstrate.
        seed pool
        ds <- dependencyPairs pool
        maximum (map length (dependentGroups ds)) `shouldSatisfy` (>= 2)

      it "leaves more than one head, so the drawing has several work streams" $ \pool -> do
        seed pool
        ds <- dependencyPairs pool
        titles <- nodeTitles pool
        let waitedOn = nub [dependency | (_, dependency) <- ds]
            -- Every node minus the root, minus those something waits on.
            headCount = length titles - 1 - length waitedOn
        headCount `shouldSatisfy` (> 1)

      it "chains a replicated node's own dependency below it" $ \pool -> do
        -- A replicated node carries its subtree with it, so the fixture
        -- has to have something *under* the shared node -- otherwise it
        -- would only ever exercise replicating a leaf.
        seed pool
        ds <- dependencyPairs pool
        let shared = [n | g@(n : _) <- dependentGroups ds, length g >= 2]
            hasOwnDependency n = any (\(dependent, _) -> dependent == n) ds
        any hasOwnDependency shared `shouldBe` True

      it "is idempotent -- seeding twice leaves one demo project" $ \pool -> do
        seed pool
        before' <- nodeTitles pool
        beforeDeps <- dependencyPairs pool
        seed pool
        after' <- nodeTitles pool
        afterDeps <- dependencyPairs pool
        projects <- projectCount pool
        sort after' `shouldBe` sort before'
        length afterDeps `shouldBe` length beforeDeps
        projects `shouldBe` 1
