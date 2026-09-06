{-# LANGUAGE OverloadedStrings #-}

module Config.DbSpec (spec) where

import Common.Validation (ValidationErr)
import Config.Db
import Control.Monad.Writer (runWriter)
import Test.Hspec

validLookup :: LookupDbConfig
validLookup =
  LookupDbConfig
    { database' = Just "typeio"
    , host' = Just "localhost"
    , password' = Just "secret"
    , port' = Just "5432"
    , poolCount' = Just "5"
    , schema' = Just "project"
    , user' = Just "typeio_user"
    }

validConfig :: DbConfig
validConfig =
  DbConfig
    { database = "typeio"
    , host = "localhost"
    , password = "secret"
    , dbPort = "5432"
    , poolCount = 5
    , schema = "project"
    , user = "typeio_user"
    }

spec :: Spec
spec = do
  describe "validateConfig" $ do
    it "succeeds with no errors when every field is present and valid" $
      runWriter (validateConfig validLookup) `shouldBe` (Just validConfig, [])

    it "records a missing-field error and still returns Nothing for that field's absence" $ do
      let (result, errs) = runWriter (validateConfig validLookup {database' = Nothing})
      result `shouldBe` Nothing
      errs `shouldBe` ["DB_DATABASE is missing from environment config"]

    it "accumulates errors from multiple missing fields, not just the first" $ do
      let (result, errs) =
            runWriter
              ( validateConfig
                  validLookup
                    { database' = Nothing
                    , host' = Nothing
                    }
              )
      result `shouldBe` Nothing
      errs
        `shouldBe` [ "DB_DATABASE is missing from environment config"
                   , "DB_HOST is missing from environment config"
                   ]

    it "rejects a non-integer pool count with a specific message" $ do
      let (result, errs) = runWriter (validateConfig validLookup {poolCount' = Just "five"})
      result `shouldBe` Nothing
      errs `shouldBe` ["DB_POOL_COUNT must be a valid integer"]

    it
      "flags a pool count above the allowed range with a specific message, but (per \
      \isBetween's own logs-but-passes-through design, see Common.ValidationSpec) still \
      \returns the out-of-range value rather than Nothing"
      $ do
        -- Pins the bound and its message to each other: isBetween 1 10,
        -- a message saying 1 and 10, and the .env value in use
        -- (DB_POOL_COUNT=10) all have to agree.
        let (result, errs) = runWriter (validateConfig validLookup {poolCount' = Just "11"})
        result `shouldBe` Just validConfig {poolCount = 11}
        errs `shouldBe` ["DB_POOL_COUNT must be between 1 and 10"]

    it "accepts a pool count at each edge of the allowed range (1 to 10)" $ do
      runWriter (validateConfig validLookup {poolCount' = Just "1"})
        `shouldBe` (Just validConfig {poolCount = 1}, [])
      runWriter (validateConfig validLookup {poolCount' = Just "10"})
        `shouldBe` (Just validConfig {poolCount = 10}, [])

    it
      "treats an empty string as present-but-invalid, NOT the same as missing -- isNotEmpty logs \
      \an error but still returns the (blank) value unchanged, so the field ends up Just \"\" \
      \rather than Nothing"
      $ do
        let (result, errs) = runWriter (validateConfig validLookup {host' = Just ""})
        result `shouldBe` Just validConfig {host = ""}
        errs `shouldBe` ["DB_HOST is missing from environment config" :: ValidationErr]

  describe "connStr" $
    it "assembles a libpq-style connection string from a DbConfig" $
      connStr validConfig
        `shouldBe` "host=localhost dbname=typeio user=typeio_user password=secret port=5432 sslmode=disable"
