{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module App.ParamsSpec (spec) where

import App.Params ()
import Config.Visualization (Visualization (..))
import Data.Either (isLeft)
import Database.Persist.Sql (toSqlKey)
import qualified Domain.Project.Model as M
import Test.Hspec
import Web.HttpApiData (parseUrlPiece, toUrlPiece)

projectId :: Int -> M.ProjectId
projectId = toSqlKey . fromIntegral

spec :: Spec
spec = do
  -- These identifiers arrive off the wire, so what matters is not that a
  -- well-formed one parses but that a malformed one is refused. The
  -- instances themselves come from persistent's mkPersist; these cases
  -- pin the behaviour the routes depend on.
  describe "FromHttpApiData for a persistent key" $ do
    it "parses a plain decimal" $
      parseUrlPiece "42" `shouldBe` Right (projectId 42)

    -- The bespoke app's valRead goes through readMaybe, which implements
    -- Haskell literal syntax: readMaybe "0x1F" :: Maybe Int is Just 31,
    -- so ?projectId=0x1F resolves to project 31 there.
    it "refuses a hex literal" $
      parseUrlPiece @M.ProjectId "0x1F" `shouldSatisfy` isLeft

    it "refuses surrounding whitespace" $
      parseUrlPiece @M.ProjectId " 42 " `shouldSatisfy` isLeft

    it "refuses a decimal point" $
      parseUrlPiece @M.ProjectId "42.0" `shouldSatisfy` isLeft

    it "refuses trailing text" $
      parseUrlPiece @M.ProjectId "42abc" `shouldSatisfy` isLeft

    it "refuses an empty value" $
      parseUrlPiece @M.ProjectId "" `shouldSatisfy` isLeft

    it "round-trips through toUrlPiece" $
      parseUrlPiece (toUrlPiece (projectId 7)) `shouldBe` Right (projectId 7)

  describe "FromHttpApiData Visualization" $ do
    it "parses the spelling used in the app's own URLs" $
      parseUrlPiece "Rootless" `shouldBe` Right Rootless

    -- Case-insensitive on the way in, canonical on the way out, so a
    -- hand-typed URL works without the round trip drifting.
    it "accepts any casing" $
      parseUrlPiece "orbital" `shouldBe` Right Orbital

    it "refuses an unknown visualization" $
      parseUrlPiece @Visualization "Layered" `shouldSatisfy` isLeft

    it "refuses a constructor-like value that is not one" $
      parseUrlPiece @Visualization "Radial" `shouldSatisfy` isLeft

    it "round-trips every visualization" $
      mapM_
        (\v -> parseUrlPiece (toUrlPiece v) `shouldBe` Right v)
        [minBound .. maxBound :: Visualization]
