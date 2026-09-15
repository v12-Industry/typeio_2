{-# LANGUAGE OverloadedStrings #-}

module Domain.System.Responder.Health where

import App.Env (AppM)
import Data.Aeson (ToJSON, object, toJSON, (.=))
import Data.Text (Text, pack)
import Platform.Build (BuildInfo (..), buildInfo)

data Health = Health
  { healthStatus :: Text
  , healthCommit :: Text
  }

instance ToJSON Health where
  toJSON h =
    object
      [ "status" .= healthStatus h
      , "commit" .= healthCommit h
      ]

handler :: AppM Health
handler =
  pure
    Health
      { healthStatus = "ok"
      , healthCommit = pack . commit $ buildInfo
      }
