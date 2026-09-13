{-# LANGUAGE ScopedTypeVariables #-}

module Common.EitherSpec (spec) where

import Common.Either
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck ((===))

spec :: Spec
spec = do
  describe "listToEither" $ do
    it "returns the head as Right for a non-empty list" $
      listToEither "empty" [1 :: Int, 2, 3] `shouldBe` Right 1
    it "returns the given error as Left for an empty list" $
      listToEither "empty" ([] :: [Int]) `shouldBe` Left "empty"
    prop "always matches the head of a non-empty list, for any list" $
      \(x :: Int) (xs :: [Int]) ->
        listToEither "empty" (x : xs) === Right x

  describe "maybeToEither" $ do
    it "returns Right for a Just" $
      maybeToEither "missing" (Just (1 :: Int)) `shouldBe` Right 1
    it "returns the given error as Left for Nothing" $
      maybeToEither "missing" (Nothing :: Maybe Int) `shouldBe` Left "missing"

  describe "notNullEither" $ do
    it "returns Right for a non-empty Foldable" $
      notNullEither "empty" [1 :: Int, 2] `shouldBe` Right [1, 2]
    it "returns the given error as Left for an empty Foldable" $
      notNullEither "empty" ([] :: [Int]) `shouldBe` Left "empty"
    it "works for any Foldable, not just lists (e.g. Maybe)" $ do
      notNullEither "empty" (Just (1 :: Int)) `shouldBe` Right (Just 1)
      notNullEither "empty" (Nothing :: Maybe Int) `shouldBe` Left "empty"
