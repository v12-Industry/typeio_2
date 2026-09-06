{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Common.ValidationSpec (spec) where

import Common.Validation
import Control.Monad.Writer (runWriter)
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck ((===))

{- | Stands in for the app's own Read-deriving enums (e.g.
Config.App.EnvironmentName), to prove valRead works for more than
just numeric types.
-}
data Color = Red | Green | Blue deriving (Show, Eq, Read)

spec :: Spec
spec = do
  describe ".$" $ do
    it "maps over a Just without recording any error" $
      runWriter (Just (3 :: Int) .$ (+ 1)) `shouldBe` (Just 4, [])
    it "passes Nothing through untouched" $
      runWriter ((Nothing :: Maybe Int) .$ (+ 1)) `shouldBe` (Nothing, [])

  describe "isThere" $ do
    it "passes a present value through with no error" $
      runWriter (isThere "missing" (Just (5 :: Int))) `shouldBe` (Just 5, [])
    it "records the given error and returns Nothing for a missing value" $
      runWriter (isThere "missing" (Nothing :: Maybe Int)) `shouldBe` (Nothing, ["missing"])
    prop "never errors on a Just, for any value" $ \(x :: Int) ->
      runWriter (isThere "missing" (Just x)) === (Just x, [])

  describe "isNotEmpty" $ do
    it "passes a non-empty value through with no error" $
      runWriter (isNotEmpty "empty" (Just ("hi" :: String))) `shouldBe` (Just "hi", [])
    it "still returns the value but records an error when it's empty" $
      runWriter (isNotEmpty "empty" (Just ("" :: String))) `shouldBe` (Just "", ["empty"])
    it "passes Nothing through with NO error -- it only checks emptiness, not presence" $
      runWriter (isNotEmpty "empty" (Nothing :: Maybe String)) `shouldBe` (Nothing, [])

  describe "valRead" $ do
    it "parses a valid value with no error" $
      (runWriter (valRead "bad int" (Just "42")) :: (Maybe Int, [ValidationErr]))
        `shouldBe` (Just 42, [])
    it "records an error and returns Nothing for an unparseable value" $
      (runWriter (valRead "bad int" (Just "not-a-number")) :: (Maybe Int, [ValidationErr]))
        `shouldBe` (Nothing, ["bad int"])
    it "passes Nothing through with NO error" $
      (runWriter (valRead "bad int" Nothing) :: (Maybe Int, [ValidationErr]))
        `shouldBe` (Nothing, [])

    -- valRead is generic (Read b => ...) -- prove it beyond Int, since
    -- Read's parsing rules aren't the same for every type.
    it "parses a Bool" $
      (runWriter (valRead "bad bool" (Just "True")) :: (Maybe Bool, [ValidationErr]))
        `shouldBe` (Just True, [])
    it "rejects a lowercase bool literal -- Read is case-sensitive on constructor names" $
      (runWriter (valRead "bad bool" (Just "true")) :: (Maybe Bool, [ValidationErr]))
        `shouldBe` (Nothing, ["bad bool"])
    it "parses a custom Read-deriving enum, the same shape as Config.App's EnvironmentName" $
      (runWriter (valRead "bad color" (Just "Red")) :: (Maybe Color, [ValidationErr]))
        `shouldBe` (Just Red, [])
    it "rejects a name that isn't one of the enum's constructors" $
      (runWriter (valRead "bad color" (Just "Purple")) :: (Maybe Color, [ValidationErr]))
        `shouldBe` (Nothing, ["bad color"])
    it
      "does NOT parse a plain unquoted word as a String -- Read requires a quoted literal, \
      \not just any input"
      $ (runWriter (valRead "bad string" (Just "hello")) :: (Maybe String, [ValidationErr]))
        `shouldBe` (Nothing, ["bad string"])
    it "does parse a properly-quoted string literal as a String" $
      (runWriter (valRead "bad string" (Just "\"hello\"")) :: (Maybe String, [ValidationErr]))
        `shouldBe` (Just "hello", [])

  describe "orDefault" $ do
    it "supplies the default for an absent value" $
      (runWriter (orDefault (7 :: Int) Nothing) :: (Maybe Int, [ValidationErr]))
        `shouldBe` (Just 7, [])

    it "leaves a present value alone" $
      (runWriter (orDefault (7 :: Int) (Just 1)) :: (Maybe Int, [ValidationErr]))
        `shouldBe` (Just 1, [])

    it "records no error of its own, ever" $
      -- The counterpart to isThere: absence is the expected case here,
      -- not the failure.
      (runWriter (orDefault 'x' Nothing) :: (Maybe Char, [ValidationErr]))
        `shouldBe` (Just 'x', [])

    it "fills the value after a failed parse but does NOT clear the error" $ do
      -- The property the whole combinator turns on. A field that was
      -- present and unparseable must still fail overall, even though
      -- this hands back a value -- otherwise "optional with a default"
      -- would silently swallow a typo.
      let w = valRead "bad int" (Just "nope") >>= orDefault (7 :: Int)
      (runWriter w :: (Maybe Int, [ValidationErr]))
        `shouldBe` (Just 7, ["bad int"])

    it "makes runValidation succeed on an absent optional field" $
      -- Without it, a pipeline ending in an absent optional field hands
      -- runValidation a (Nothing, []) -- no value, no errors -- which it
      -- reports as "Unknown error in validation".
      runValidation
        id
        (valRead "bad int" Nothing >>= orDefault (7 :: Int))
        `shouldBe` (Right 7 :: Either [ValidationErr] Int)

    it "still fails overall when the value was present and wrong" $
      runValidation
        id
        (valRead "bad int" (Just "nope") >>= orDefault (7 :: Int))
        `shouldBe` (Left ["bad int"] :: Either [ValidationErr] Int)

  describe "isBetween" $ do
    it "passes an in-range value through with no error" $
      runWriter (isBetween 1 10 "out of range" (Just (5 :: Int))) `shouldBe` (Just 5, [])
    it "still returns the value but records an error when out of range" $
      runWriter (isBetween 1 10 "out of range" (Just (99 :: Int)))
        `shouldBe` (Just 99, ["out of range"])
    it "passes Nothing through with NO error" $
      runWriter (isBetween 1 10 "out of range" (Nothing :: Maybe Int)) `shouldBe` (Nothing, [])

  describe "runValidation" $ do
    it "succeeds when the value is present and no errors were recorded" $
      runValidation id (isThere "missing" (Just (1 :: Int)))
        `shouldBe` (Right 1 :: Either [ValidationErr] Int)

    it
      "fails with the recorded errors even when the value is still Just -- this is what \
      \makes isBetween/isNotEmpty/isEq's \"pass the value through but still record an \
      \error\" behavior actually reject the input overall"
      $ runValidation id (isBetween 1 10 "out of range" (Just (99 :: Int)))
        `shouldBe` (Left ["out of range"] :: Either [ValidationErr] Int)

    it
      "falls back to a generic \"Unknown error\" for a (Nothing, []) result -- reachable \
      \when a Nothing-passthrough check (isNotEmpty/isBetween/isEq/valRead) runs on a \
      \Nothing that was never actually flagged by isThere first"
      $ runValidation id (isNotEmpty "empty" (Nothing :: Maybe String))
        `shouldBe` (Left ["Unknown error in validation"] :: Either [ValidationErr] String)

  describe "errcat" $
    it "concatenates a String key with a Text message" $
      errcat "WEB_PORT" " is missing" `shouldBe` "WEB_PORT is missing"
