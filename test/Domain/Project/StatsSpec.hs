{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.StatsSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Domain.Project.Stats
  ( ProjectStats (..)
  , StatusCount (..)
  , projectStats
  )
import Test.Hspec

spec :: Spec
spec = do
  describe "projectStats" $ do
    it "counts every node it is given" $
      psTotal (projectStats vocabulary (Map.fromList [("open", 3), ("closed", 1)]))
        `shouldBe` 4

    -- The vocabulary is the status table, so a status nothing is sitting
    -- in is still a row in the panel. A project with no rejected work
    -- reads "Rejected 0", not a panel that quietly omits the line.
    it "gives every status in the vocabulary a row, in vocabulary order" $
      psByStatus (projectStats vocabulary (Map.fromList [("closed", 2)]))
        `shouldBe` [ StatusCount "active" 0
                   , StatusCount "closed" 2
                   , StatusCount "open" 0
                   , StatusCount "rejected" 0
                   ]

    it "reports completion as the closed share of the total" $
      psCompletion (projectStats vocabulary (Map.fromList [("closed", 1), ("open", 3)]))
        `shouldBe` 25

    it "rounds completion to a whole percent" $
      psCompletion (projectStats vocabulary (Map.fromList [("closed", 1), ("open", 2)]))
        `shouldBe` 33

    it "reports a fully closed project as 100" $
      psCompletion (projectStats vocabulary (Map.fromList [("closed", 5)]))
        `shouldBe` 100

    -- Nothing done out of nothing at all is 0%, not a division by zero.
    it "reports an empty project as zero rather than dividing by zero" $
      projectStats vocabulary Map.empty
        `shouldBe` ProjectStats
          { psTotal = 0
          , psByStatus =
              [ StatusCount "active" 0
              , StatusCount "closed" 0
              , StatusCount "open" 0
              , StatusCount "rejected" 0
              ]
          , psCompletion = 0
          }

    it "still totals statuses the vocabulary has no row for" $
      psTotal (projectStats ["open"] (Map.fromList [("open", 1), ("archived", 2)]))
        `shouldBe` 3

vocabulary :: [Text]
vocabulary = ["active", "closed", "open", "rejected"]
