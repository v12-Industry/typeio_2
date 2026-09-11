{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Data.Text.UtilSpec (spec) where

import Data.Char (isAsciiLower, isDigit)
import Data.Text (pack)
import qualified Data.Text as T
import Data.Text.Util (intToText, slug, wrapLabel)
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

  describe "slug" $ do
    it "leaves an already-safe token alone" $
      slug "active" `shouldBe` "active"
    it "lowercases" $
      slug "Rejected" `shouldBe` "rejected"
    it "joins words with a single dash" $
      slug "in progress" `shouldBe` "in-progress"
    it "collapses a run of separators rather than emitting empty pieces" $
      slug "not __ started" `shouldBe` "not-started"
    it "drops leading and trailing separators" $
      slug "  on hold  " `shouldBe` "on-hold"
    it "keeps digits" $
      slug "phase 2" `shouldBe` "phase-2"
    -- The status vocabulary is a database table, so a value can be
    -- anything a row holds. Nothing that reaches a class name may
    -- escape the identifier: a status of `" onclick` has to come back
    -- as something inert, not as an attribute boundary.
    it "strips characters that would break out of a class attribute" $
      slug "\" onclick=\"x()" `shouldBe` "onclick-x"
    it "gives an all-separator value nothing rather than a bare dash" $
      slug "   " `shouldBe` ""
    prop "never emits anything outside [a-z0-9-], whatever it is given" $
      \(s :: String) ->
        T.all (\c -> c == '-' || isAsciiLower c || isDigit c) (slug (pack s))

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
