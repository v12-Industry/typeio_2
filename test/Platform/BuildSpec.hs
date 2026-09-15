{-# LANGUAGE OverloadedStrings #-}

module Platform.BuildSpec (spec) where

import Data.Aeson (encode, object, toJSON, (.=))
import Platform.Build (BuildInfo (..), resolveCommit, unknownCommit)
import Test.Hspec

aCommit :: String
aCommit = "0329aef1739cd1f62ff44fe519c937dc87abd170"

anotherCommit :: String
anotherCommit = "6f6020a204742649c3ffbad16eb5fd7409849a38"

spec :: Spec
spec = do
  describe "resolveCommit" $ do
    it "prefers the injected commit over the checked-out one" $
      -- A binary shipped without its checkout carries its commit in the
      -- environment; whatever the local checkout says where it happens
      -- to be running is not the commit it was built from.
      resolveCommit (Just aCommit) (Just anotherCommit) `shouldBe` aCommit

    it "falls back to the checked-out commit when nothing is injected" $
      resolveCommit Nothing (Just aCommit) `shouldBe` aCommit

    it "trims the trailing newline the rev-parse output carries" $
      resolveCommit Nothing (Just (aCommit ++ "\n")) `shouldBe` aCommit

    it "reports an explicit unknown when neither source has a commit" $
      resolveCommit Nothing Nothing `shouldBe` unknownCommit

    it "ignores a blank injected value" $
      -- An exported-but-empty BUILD_COMMIT is an unset one, not an answer.
      resolveCommit (Just "  ") (Just aCommit) `shouldBe` aCommit

    it "ignores anything that is not a full hash" $
      -- The endpoint exists to name one exact commit, so an abbreviated
      -- hash, a branch name or a tag is not an answer either.
      map (`resolveCommit` Nothing) [Just "0329aef", Just "main", Just "v1.2.3", Just (aCommit ++ "0")]
        `shouldBe` replicate 4 unknownCommit

    it "never reports an empty commit" $
      resolveCommit (Just "") (Just "") `shouldNotBe` ""

  describe "its JSON" $ do
    it "names the field `commit`" $
      -- The response field is the contract the endpoint publishes;
      -- renaming it silently would break whoever reads it.
      encode (BuildInfo {commit = "abc123"})
        `shouldBe` encode (object ["commit" .= ("abc123" :: String)])

    it "carries the hash through unchanged" $
      toJSON (BuildInfo {commit = "abc123"})
        `shouldBe` object ["commit" .= ("abc123" :: String)]
