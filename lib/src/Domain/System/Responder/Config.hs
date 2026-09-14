{-# LANGUAGE OverloadedStrings #-}

module Domain.System.Responder.Config where

import App.Env (AppM, Env (..))
import Config.App (AppConfig (..), EnvironmentName (..))
import Config.Db (DbConfig (..), connStr)
import Control.Monad.Reader (asks)
import Data.Aeson (ToJSON, object, toJSON, (.=))
import Platform.Build (BuildInfo)

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

configDisplay :: BuildInfo -> AppConfig -> ConfigDisplay
configDisplay bd cfg = ConfigDisplay cf cs bd
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
handler = configDisplay <$> asks envBuild <*> asks envConfig
