{-# LANGUAGE OverloadedStrings #-}

module Domain.System.Responder.Config where

import App.Env (AppM, Env (..))
import Config.App (AppConfig (..), EnvironmentName (..))
import Config.Db (DbConfig (..), connStr)
import Control.Monad.Reader (asks)
import Data.Aeson (ToJSON, object, toJSON, (.=))
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

configDisplay :: AppConfig -> ConfigDisplay
configDisplay cfg = ConfigDisplay cf cs buildInfo
  where
    ev = envName cfg
    cf = preprocessConfig ev cfg
    cs = maskField ev . connStr . dbConf $ cf

maskField :: EnvironmentName -> String -> String
maskField Production _ = replicate 22 '*'
maskField _ fld = fld

preprocessConfig :: EnvironmentName -> AppConfig -> AppConfig
preprocessConfig env cfg = cfg {dbConf = db'}
  where
    d = dbConf cfg
    db' = d {password = maskField env (password d)}

handler :: AppM ConfigDisplay
handler = asks (configDisplay . envConfig)
