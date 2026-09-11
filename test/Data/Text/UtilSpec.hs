{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Data.Text.UtilSpec (spec) where

import Data.Text (pack)
import qualified Data.Text as T
import Data.Text.Util (intToText, wrapLabel)
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck ((===))

spec :: Spec
spec = do
  describe "intToText" $ do
    it "renders a positive Int the same as show" $
      intToText (42 :: Int) `shouldBe` "42"
    it "renders zero" $
      intToText (0 :: Int) `shouldBe` "0"
    it "works for any Integral, not just Int (e.g. Integer)" $
      intToText (123456789012345 :: Integer) `shouldBe` "123456789012345"
    prop "always matches Data.Text.pack . show, for any Int" $
      \(n :: Int) -> intToText n === pack (show n)

  describe "wrapLabel" $ do
    it "leaves a label that already fits on one line alone" $
      wrapLabel 14 3 "HVAC" `shouldBe` ["HVAC"]
    it "collapses the whitespace it wraps on" $
      wrapLabel 14 3 "  HVAC   Ductwork  " `shouldBe` ["HVAC Ductwork"]
    it "greedily fills each line up to the width" $
      wrapLabel 14 3 "Insulation & Drywall" `shouldBe` ["Insulation &", "Drywall"]
    it "wraps a long real-world node title across lines" $
      wrapLabel 14 3 "Foundation Repair & Underpinning"
        `shouldBe` ["Foundation", "Repair &", "Underpinning"]
    it "truncates with an ellipsis past maxLines rather than dropping text silently" $
      wrapLabel 14 2 "Final Inspection & Occupancy Certification"
        `shouldBe` ["Final", "Inspection &…"]
    it "hard-splits a single word too long to fit rather than overflowing" $
      wrapLabel 5 3 "Supercalifragilistic"
        `shouldBe` ["Super", "calif", "ragi…"]
    it "returns no lines for empty or whitespace-only input" $ do
      wrapLabel 14 3 "" `shouldBe` []
      wrapLabel 14 3 "   " `shouldBe` []
    it "returns no lines for a nonsensical width or line count" $ do
      wrapLabel 0 3 "HVAC" `shouldBe` []
      wrapLabel 14 0 "HVAC" `shouldBe` []
    prop "never emits more than maxLines lines" $
      \(s :: String) ->
        length (wrapLabel 14 3 (pack s)) <= 3
    prop "never emits a line wider than the requested width" $
      \(s :: String) ->
        all ((<= 14) . T.length) (wrapLabel 14 3 (pack s))
