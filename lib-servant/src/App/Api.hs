{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module App.Api
  ( Api
  , ManageProjectUi
  , Health (..)
  , api
  ) where

import App.Html (HTML)
import Config.Visualization (Visualization)
import Data.Aeson (ToJSON, object, toJSON, (.=))
import Data.Int (Int64)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Domain.System.Responder.Config (ConfigDisplay)
import Lucid (Html)
import Servant.API
  ( Get
  , JSON
  , Optional
  , Post
  , QueryParam'
  , Required
  , Strict
  , (:<|>)
  , (:>)
  )

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

-- Every parameter is Strict: a malformed one is a 400 before a handler
-- runs, rather than being coerced or silently defaulted.
type ProjectIdParam = QueryParam' '[Required, Strict] "projectId" Int64

type VisualizationParam =
  QueryParam' '[Optional, Strict] "visualizationMode" Visualization

type ViewParam n = QueryParam' '[Optional, Strict] n Double

type ManageProjectUi =
  "vw"
    :> ProjectIdParam
    :> QueryParam' '[Optional, Strict] "nodeId" Int64
    :> VisualizationParam
    :> ViewParam "viewX"
    :> ViewParam "viewY"
    :> ViewParam "viewScale"
    :> Get '[HTML] (Html ())
    :<|> "graph"
      :> ProjectIdParam
      :> VisualizationParam
      :> Get '[HTML] (Html ())

type Api =
  "healthz" :> Get '[JSON] Health
    :<|> "ui" :> "central" :> "empty" :> Get '[HTML] (Html ())
    :<|> "api" :> "central" :> "seed-database" :> Post '[JSON] Text
    :<|> "api" :> "system" :> "config" :> Get '[JSON] ConfigDisplay
    :<|> "ui" :> "project" :> ManageProjectUi

api :: Proxy Api
api = Proxy
