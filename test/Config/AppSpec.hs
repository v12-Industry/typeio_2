{-# LANGUAGE OverloadedStrings #-}

module Config.AppSpec (spec) where

import Config.App
import Config.Visualization (Visualization (..))
import Config.Web (port)
import System.Environment (setEnv, unsetEnv)
import Test.Hspec

-- Config.App.loadAppConfig doesn't separate its validation logic into a
-- pure function taking a constructed lookup value the way Config.Db and
-- Config.Web do -- it reads the environment directly and delegates to
-- them. So unlike DbSpec/WebSpec, this exercises the real IO boundary
-- via setEnv/unsetEnv rather than a pure Writer computation. Every test
-- sets a complete, valid baseline first and only overrides what it's
-- testing, since these are real process-global environment variables.

setValidEnv :: IO ()
setValidEnv = do
  setEnv "ENV" "Local"
  setEnv "DB_DATABASE" "typeio"
  setEnv "DB_HOST" "localhost"
  setEnv "DB_PASS" "secret"
  setEnv "DB_PORT" "5432"
  setEnv "DB_POOL_COUNT" "5"
  setEnv "DB_SCHEMA" "project"
  setEnv "DB_USER" "typeio_user"
  setEnv "WEB_INDEX_REDIRECT" "/ui/projects/vw"
  setEnv "WEB_PORT" "8080"
  setEnv "WEB_REQUEST_ID_HEADER" "X-Request-Id"
  setEnv "GRAPH_VISUALIZATION" "Layered"

spec :: Spec
spec = around_ (setValidEnv >>) $
  describe "loadAppConfig" $ do
    it "succeeds when every required variable is set and valid" $ do
      result <- loadAppConfig
      case result of
        Right cfg -> envName cfg `shouldBe` Local
        Left errs -> expectationFailure ("expected success, got: " ++ show errs)

    it "fails with an error naming ENV when it's missing" $ do
      unsetEnv "ENV"
      result <- loadAppConfig
      result `shouldBe` Left ["ENV is missing from environment config"]

    it "fails with a distinct message when ENV is set but not a valid EnvironmentName" $ do
      setEnv "ENV" "NotARealEnvironment"
      result <- loadAppConfig
      result `shouldBe` Left ["Invalid environment value"]

    it "accumulates errors across ENV, DB, and web config together, not just the first" $ do
      unsetEnv "ENV"
      unsetEnv "DB_HOST"
      unsetEnv "WEB_INDEX_REDIRECT"
      result <- loadAppConfig
      result
        `shouldBe` Left
          [ "ENV is missing from environment config"
          , "DB_HOST is missing from environment config"
          , "WEB_INDEX_REDIRECT is missing from environment config"
          ]

    -- The four GRAPH_VISUALIZATION cases that used to sit here are gone
    -- with the variable (#223): which drawing to render is a property of
    -- a request now, not of the process, so there is nothing for
    -- loadAppConfig to read or reject. The equivalent coverage lives in
    -- Domain.Project.Visualization.Common's validateVisualization and
    -- its integration spec -- including the case those tests existed
    -- for, an unrecognised value being an error rather than a silent
    -- fallback.

    it "succeeds even when WEB_PORT is unset, defaulting to 3000 (see Config.Web.defaultWebPort)" $ do
      unsetEnv "WEB_PORT"
      result <- loadAppConfig
      case result of
        Right cfg -> port (webConf cfg) `shouldBe` 3000
        Left errs -> expectationFailure ("expected success, got: " ++ show errs)

    it
      "rejects an out-of-range DB_POOL_COUNT overall, even though Config.Db.validateConfig \
      \alone doesn't turn it into Nothing (see Config.DbSpec) -- it's this level's \
      \runValidation that actually checks the accumulated error list, not any single field's \
      \own Maybe"
      $ do
        setEnv "DB_POOL_COUNT" "12"
        result <- loadAppConfig
        result `shouldBe` Left ["DB_POOL_COUNT must be between 1 and 10"]
