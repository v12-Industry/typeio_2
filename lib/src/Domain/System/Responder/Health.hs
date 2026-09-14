{-# LANGUAGE OverloadedStrings #-}

module Domain.System.Responder.Health where

import App.Env (AppM, Env (..))
import Control.Monad.Reader (asks)
import Data.Aeson (ToJSON, object, toJSON, (.=))
import Data.Text (Text, pack)
import Platform.Build (BuildInfo (..))

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
handler = asks (templateHealth . envBuild)

templateHealth :: BuildInfo -> Health
templateHealth bi =
  Health
    { healthStatus = "ok"
    , healthCommit = pack . commit $ bi
    }
