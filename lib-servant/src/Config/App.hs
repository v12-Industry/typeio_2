{-# LANGUAGE OverloadedStrings #-}

module Config.App where

import Common.Validation
  ( ValidationErr
  , isThere
  , runValidation
  , valRead
  , (.$)
  )
import Config.Db (DbConfig, loadDbConfig)
import Config.Web (WebConfig (..), loadWebConfig)
import Data.Aeson (ToJSON, object, toJSON, (.=))
import Data.Text (pack, unpack)
import System.Environment (lookupEnv)

keyEnv :: String
keyEnv = "ENV"

data AppConfig = AppConfig
  { envName :: EnvironmentName
  , dbConf :: DbConfig
  , webConf :: WebConfig
  }
  deriving (Eq, Read, Show)

instance ToJSON AppConfig where
  toJSON cfg =
    object
      [ "env" .= envName cfg
      , "db" .= dbConf cfg
      , "web" .= webConf cfg
      ]

data EnvironmentName = Local | Development | Production
  deriving (Eq, Read, Show)

instance ToJSON EnvironmentName where
  toJSON = toJSON . show

loadAppConfig :: IO (Either [ValidationErr] AppConfig)
loadAppConfig = do
  env <- lookupEnv keyEnv
  db <- loadDbConfig
  web <- loadWebConfig
  return $ runValidation id $ do
    env' <-
      env
        .$ id
        >>= isThere (er keyEnv)
        >>= valRead "Invalid environment value"
    db' <- db
    web' <- web
    return $ AppConfig <$> env' <*> db' <*> web'
  where
    er k = pack k <> " is missing from environment config"

loadConfig :: IO AppConfig
loadConfig = do
  res <- loadAppConfig
  case res of
    Left errs -> error $ "Failed to load configuration: " ++ (unlines . map unpack $ errs)
    Right c -> return c

webDefaultPath :: AppConfig -> String
webDefaultPath = indexRedirect . webConf
