{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Domain.Project.Node.StatusSpec (spec) where

import Data.List (nub)
import qualified Data.Text as T
import Domain.Project.Node.Status
  ( NodeStatus (..)
  , nodeStatusClass
  , nodeStatusFromKey
  )
import Test.Hspec
import Test.Hspec.QuickCheck (prop)

spec :: Spec
spec = do
  describe "nodeStatusFromKey" $ do
    it "recognises each seeded status id" $ do
      nodeStatusFromKey "open" `shouldBe` Just StatusOpen
      nodeStatusFromKey "active" `shouldBe` Just StatusActive
      nodeStatusFromKey "closed" `shouldBe` Just StatusClosed
      nodeStatusFromKey "rejected" `shouldBe` Just StatusRejected
    it "ignores casing and surrounding whitespace" $ do
      nodeStatusFromKey "Rejected" `shouldBe` Just StatusRejected
      nodeStatusFromKey "  ACTIVE " `shouldBe` Just StatusActive
    -- The vocabulary is a database table, so a row can hold a value the
    -- app has no drawing for. That case is nothing, not a class built
    -- out of whatever the row said.
    it "gives nothing for a status outside the vocabulary" $ do
      nodeStatusFromKey "on hold" `shouldBe` Nothing
      nodeStatusFromKey "" `shouldBe` Nothing
    prop "never accepts arbitrary text as a status" $
      \(s :: String) ->
        case nodeStatusFromKey (T.pack s) of
          Nothing -> True
          Just st -> st `elem` [minBound .. maxBound]

  describe "nodeStatusClass" $ do
    it "names the class the stylesheet draws" $ do
      nodeStatusClass StatusOpen `shouldBe` "status-open"
      nodeStatusClass StatusActive `shouldBe` "status-active"
      nodeStatusClass StatusClosed `shouldBe` "status-closed"
      nodeStatusClass StatusRejected `shouldBe` "status-rejected"
    -- Two statuses sharing a class would draw as one colour, silently.
    it "gives every status its own class" $ do
      let classes = map nodeStatusClass [minBound .. maxBound :: NodeStatus]
      nub classes `shouldBe` classes
    it "round-trips a class back through the key it came from" $
      mapM_
        (\st -> nodeStatusFromKey (T.drop 7 (nodeStatusClass st)) `shouldBe` Just st)
        [minBound .. maxBound :: NodeStatus]
