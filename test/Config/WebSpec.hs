{-# LANGUAGE OverloadedStrings #-}

module Config.WebSpec (spec) where

import Common.Validation (ValidationErr)
import Config.Web
import Control.Monad.Writer (runWriter)
import Data.CaseInsensitive (mk)
import Test.Hspec

validLookup :: LookupWebConfig
validLookup =
  LookupWebConfig
    { loadIndexRedirect = Just "/ui/projects/vw"
    , loadPort = Just "8080"
    , loadRequestIdHeader = Just "X-Request-Id"
    }

validConfig :: WebConfig
validConfig =
  WebConfig
    { indexRedirect = "/ui/projects/vw"
    , port = 8080
    , requestIdHeader = mk "X-Request-Id"
    }

spec :: Spec
spec = do
  describe "validateConfig" $ do
    it "succeeds with no errors when every field is present and valid" $
      runWriter (validateConfig validLookup) `shouldBe` (Just validConfig, [])

    it "records an error for a missing index redirect" $ do
      let (result, errs) = runWriter (validateConfig validLookup {loadIndexRedirect = Nothing})
      result `shouldBe` Nothing
      errs `shouldBe` ["WEB_INDEX_REDIRECT is missing from environment config" :: ValidationErr]

    it "records an error for a missing request-id header" $ do
      let (result, errs) = runWriter (validateConfig validLookup {loadRequestIdHeader = Nothing})
      result `shouldBe` Nothing
      errs `shouldBe` ["WEB_REQUEST_ID_HEADER is missing from environment config" :: ValidationErr]

    it "rejects a non-integer port with a specific message" $ do
      let (result, errs) = runWriter (validateConfig validLookup {loadPort = Just "not-a-number"})
      result `shouldBe` Nothing
      errs `shouldBe` ["WEB_PORT must be a valid integer"]

    it "accepts a port at each edge of the allowed range (1 to 65535)" $ do
      runWriter (validateConfig validLookup {loadPort = Just "1"})
        `shouldBe` (Just validConfig {port = 1}, [])
      runWriter (validateConfig validLookup {loadPort = Just "65535"})
        `shouldBe` (Just validConfig {port = 65535}, [])

    it
      "flags an out-of-range port with a specific message, but (per isBetween's \
      \logs-but-passes-through design, see Common.ValidationSpec) still returns the \
      \out-of-range value rather than Nothing"
      $ do
        -- The message has to be specific to this check. Reusing the
        -- generic "missing from environment config" one here would
        -- actively mislead anyone debugging an out-of-range (not
        -- missing) port.
        let (result, errs) = runWriter (validateConfig validLookup {loadPort = Just "99999"})
        result `shouldBe` Just validConfig {port = 99999}
        errs `shouldBe` ["WEB_PORT must be between 1 and 65535" :: ValidationErr]

  describe "lookupWebConfig / defaultWebPort integration" $ do
    it "defaultWebPort is \"3000\", matching what make seed-db assumes" $
      defaultWebPort `shouldBe` "3000"
