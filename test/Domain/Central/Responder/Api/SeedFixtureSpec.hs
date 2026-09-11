{-# LANGUAGE OverloadedStrings #-}

{- | The demo fixtures as data, before any database is involved.

A typo in a fixture only shows up as a foreign-key violation at seed
time, or -- worse -- as a dependency that silently never gets inserted
because its key matches nothing. Both are cheap to rule out here.
-}
module Domain.Central.Responder.Api.SeedFixtureSpec (spec) where

import Data.List (nub, sort)
import Domain.Central.Responder.Api.Seed
  ( DemoProject (..)
  , DemoWork (..)
  , demoProjects
  , nodeStatuses
  )
import Domain.Project.Model (NodeStatus (..))
import Test.Hspec

spec :: Spec
spec = do
  describe "the demo fixtures" $ do
    it "gives every project a distinct title, since seeding keys on it" $ do
      let titles = map dpTitle demoProjects
      nub titles `shouldBe` titles

    it "names a status the seed actually inserts" $
      mapM_
        ( \w ->
            dwStatus w `shouldSatisfy` (`elem` statusIds)
        )
        (concatMap dpWork demoProjects)

    -- A dependency naming a key no work node has is dropped on the way
    -- into the database, so the fixture would look right here and come
    -- out missing an edge.
    it "only depends on work the same project declares" $
      mapM_
        ( \p ->
            let keys = map dwKey (dpWork p)
                referenced = concatMap (\(a, b) -> [a, b]) (dpDependencies p)
             in mapM_ (\k -> (dpTitle p, k) `shouldSatisfy` (\(_, k') -> k' `elem` keys)) referenced
        )
        demoProjects

    it "gives each project's work distinct keys" $
      mapM_
        ( \p ->
            let keys = map dwKey (dpWork p)
             in nub keys `shouldBe` keys
        )
        demoProjects

    it "never makes a work node wait on itself" $
      mapM_
        ( \p ->
            mapM_ (\(a, b) -> a `shouldSatisfy` (/= b)) (dpDependencies p)
        )
        demoProjects

    -- The point of a fixture set: a reviewer opening the app sees
    -- projects that differ, not six copies of one shape.
    it "covers every status across the set" $
      sort (nub (map dwStatus (concatMap dpWork demoProjects)))
        `shouldBe` sort statusIds

    it "varies in size, including an empty project and a large one" $ do
      let sizes = map (length . dpWork) demoProjects
      minimum sizes `shouldBe` 0
      maximum sizes `shouldSatisfy` (>= 10)
      length (nub sizes) `shouldSatisfy` (>= 4)

    it "varies in shape, from no dependencies at all to a shared bottleneck" $ do
      let shapes = map (length . dpDependencies) demoProjects
          dependents p = map fst (dpDependencies p)
          shared p = length (dependents p) /= length (nub (map snd (dpDependencies p)))
      minimum shapes `shouldBe` 0
      any shared demoProjects `shouldBe` True

statusIds :: [String]
statusIds = [s | NodeStatus s <- nodeStatuses]
