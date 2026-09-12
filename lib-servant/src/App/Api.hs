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
import Lucid (Html)
import Servant.API (Get, JSON, (:<|>), (:>))

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
    :<|> Get '[HTML] (Html ())

api :: Proxy Api
api = Proxy
