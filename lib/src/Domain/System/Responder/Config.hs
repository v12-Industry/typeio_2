{-# LANGUAGE OverloadedStrings #-}

module Domain.System.Responder.Config where

import Config.App (AppConfig (..), EnvironmentName (..))
import Config.Db (DbConfig (..), connStr)
import Data.Aeson (ToJSON, encode, object, toJSON, (.=))
import Network.HTTP.Types (status200)
import Network.Wai (Response, ResponseReceived, responseLBS)
import Platform.Build (BuildInfo, buildInfo)

data ConfigDisplay = ConfigDisplay
  { configuration :: AppConfig
  , connectionString :: String
  , build :: BuildInfo
  }

instance ToJSON ConfigDisplay where
  toJSON (ConfigDisplay cf cs bd) =
    object
      [ "config" .= cf
      , "connectionString" .= cs
      , "build" .= bd
      ]

handleGetConfig :: AppConfig -> (Response -> IO ResponseReceived) -> IO ResponseReceived
handleGetConfig cfg respond = do
  let ev = envName cfg
      cf = preprocessConfig ev cfg
      cs = maskField ev (connStr . dbConf $ cf)
      cd = ConfigDisplay cf cs buildInfo
      js = encode cd
  respond $ responseLBS status200 [("Content-Type", "application/json")] js

maskField :: EnvironmentName -> String -> String
maskField Production _ = replicate 22 '*'
maskField _ fld = fld

preprocessConfig :: EnvironmentName -> AppConfig -> AppConfig
preprocessConfig env cfg = cfg {dbConf = db'}
  where
    d = dbConf cfg
    db' = d {password = maskField env (password d)}
