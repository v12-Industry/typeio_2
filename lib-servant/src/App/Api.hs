{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module App.Api
  ( Api
  , Health (..)
  , api
  ) where

import App.Html (HTML)
import Data.Aeson (ToJSON, object, toJSON, (.=))
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Domain.System.Responder.Config (ConfigDisplay)
import Lucid (Html)
import Servant.API (Get, JSON, Post, (:<|>), (:>))

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

type Api =
  "healthz" :> Get '[JSON] Health
    :<|> "ui" :> "central" :> "empty" :> Get '[HTML] (Html ())
    :<|> "api" :> "central" :> "seed-database" :> Post '[JSON] Text
    :<|> "api" :> "system" :> "config" :> Get '[JSON] ConfigDisplay

api :: Proxy Api
api = Proxy
