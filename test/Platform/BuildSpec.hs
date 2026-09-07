{-# LANGUAGE OverloadedStrings #-}

module Platform.BuildSpec (spec) where

import Data.Aeson (encode, object, toJSON, (.=))
import Data.Char (isHexDigit)
import Platform.Build (BuildInfo (..), buildInfo, unknownCommit)
import Test.Hspec

spec :: Spec
spec = do
  describe "buildInfo" $ do
    it "reports either a full commit hash or an explicit unknown" $
      -- The build embeds whatever git could tell it. In a checkout that
      -- is a 40-character hash; in a source tarball with no .git there
      -- is nothing to read, and saying so is the honest answer. An
      -- empty string is neither, and is what this rules out.
      commit buildInfo `shouldSatisfy` \c ->
        c == unknownCommit || (length c == 40 && all isHexDigit c)

    it "never reports an empty commit" $
      commit buildInfo `shouldNotBe` ""

  describe "its JSON" $ do
    it "names the field `commit`" $
      -- The response field is the contract the endpoint publishes;
      -- renaming it silently would break whoever reads it.
      encode (BuildInfo {commit = "abc123"})
        `shouldBe` encode (object ["commit" .= ("abc123" :: String)])

    it "carries the hash through unchanged" $
      toJSON (BuildInfo {commit = "abc123"})
        `shouldBe` object ["commit" .= ("abc123" :: String)]
