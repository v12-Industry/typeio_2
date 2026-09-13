{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module App.Api
  ( Api
  , CreateProjectUi
  , HxRedirect
  , ProjectsUi
  , Health (..)
  , api
  ) where

import App.Html (HTML)
import Data.Aeson (ToJSON, object, toJSON, (.=))
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Domain.System.Responder.Config (ConfigDisplay)
import Lucid (Html)
import Servant.API
  ( FormUrlEncoded
  , Get
  , Header
  , Headers
  , JSON
  , Post
  , ReqBody
  , (:<|>)
  , (:>)
  )
import Web.FormUrlEncoded (Form)

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

-- htmx redirects by header rather than by status, so the success and
-- failure arms of a submit share one status and differ by whether the
-- header is present.
type HxRedirect = Headers '[Header "HX-Location" Text] (Html ())

type ProjectsUi =
  "vw" :> Get '[HTML] (Html ())
    :<|> "list" :> Get '[HTML] (Html ())

type CreateProjectUi =
  "vw" :> Get '[HTML] (Html ())
    :<|> "submit" :> ReqBody '[FormUrlEncoded] Form :> Post '[HTML] HxRedirect

type Api =
  "healthz" :> Get '[JSON] Health
    :<|> "ui" :> "central" :> "empty" :> Get '[HTML] (Html ())
    :<|> "api" :> "central" :> "seed-database" :> Post '[JSON] Text
    :<|> "api" :> "system" :> "config" :> Get '[JSON] ConfigDisplay
    :<|> "ui" :> "projects" :> ProjectsUi
    :<|> "ui" :> "create-project" :> CreateProjectUi

api :: Proxy Api
api = Proxy
