{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module App.Api
  ( Api
  , ProjectApi
  , ProjectsUi
  , CreateProjectUi
  , ManageProjectUi
  , NodeUi
  , CreatedNode (..)
  , HxRedirect
  , Health (..)
  , api
  ) where

import App.Html (HTML)
import Config.Visualization (Visualization)
import Data.Aeson (ToJSON, object, toJSON, (.=))
import Data.Int (Int64)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import qualified Domain.Project.Responder.Api.Node.Get as NodeGet
import qualified Domain.Project.Responder.Api.NodeStatus.Get as NodeStatusGet
import qualified Domain.Project.Responder.Api.NodeType.Get as NodeTypeGet
import qualified Domain.Project.Responder.Api.Project.Get as ProjectGet
import Domain.System.Responder.Config (ConfigDisplay)
import Lucid (Html)
import Servant.API
  ( FormUrlEncoded
  , Get
  , Header
  , Headers
  , JSON
  , NoContent
  , Optional
  , Post
  , PostCreated
  , QueryParam'
  , ReqBody
  , Required
  , StdMethod (GET)
  , Strict
  , UVerb
  , WithStatus
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

newtype CreatedNode = CreatedNode
  { createdNodeId :: Int64
  }

instance ToJSON CreatedNode where
  toJSON n = object ["nodeId" .= createdNodeId n]

type ProjectApi =
  "nodes" :> Get '[JSON] [NodeGet.Node]
    :<|> "nodes"
      :> ReqBody '[FormUrlEncoded] Form
      :> PostCreated '[JSON] (Headers '[Header "Location" Text] CreatedNode)
    :<|> "node-statuses" :> Get '[JSON] [NodeStatusGet.NodeStatus]
    :<|> "node-types" :> Get '[JSON] [NodeTypeGet.NodeType]
    :<|> "projects" :> Get '[JSON] [ProjectGet.Project]

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

-- Every parameter is Strict: a malformed one is a 400 before a handler
-- runs, rather than being coerced or silently defaulted.
type ProjectIdParam = QueryParam' '[Required, Strict] "projectId" Int64

type VisualizationParam =
  QueryParam' '[Optional, Strict] "visualizationMode" Visualization

type ViewParam n = QueryParam' '[Optional, Strict] n Double

type NodeIdParam = QueryParam' '[Required, Strict] "nodeId" Int64

-- A refresh whose client-held title already matches the stored one answers
-- 204, which htmx treats as "nothing to swap". The two outcomes are distinct
-- status codes on one route, so the union verb states both.
type NodeUi =
  "panel" :> ProjectIdParam :> NodeIdParam :> Get '[HTML] (Html ())
    :<|> "detail" :> ProjectIdParam :> NodeIdParam :> Get '[HTML] (Html ())
    :<|> "edit" :> ProjectIdParam :> NodeIdParam :> Get '[HTML] (Html ())
    :<|> "refresh"
      :> ProjectIdParam
      :> NodeIdParam
      :> QueryParam' '[Required, Strict] "clientTitle" Text
      :> QueryParam' '[Optional, Strict] "wrapWidth" Int
      :> UVerb 'GET '[HTML] '[WithStatus 200 (Html ()), WithStatus 204 NoContent]

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
    :<|> "node" :> NodeUi

type Api =
  "healthz" :> Get '[JSON] Health
    :<|> "ui" :> "central" :> "empty" :> Get '[HTML] (Html ())
    :<|> "api" :> "central" :> "seed-database" :> Post '[JSON] Text
    :<|> "api" :> "system" :> "config" :> Get '[JSON] ConfigDisplay
    :<|> "api" :> "project" :> ProjectApi
    :<|> "ui" :> "projects" :> ProjectsUi
    :<|> "ui" :> "create-project" :> CreateProjectUi
    :<|> "ui" :> "project" :> ManageProjectUi

api :: Proxy Api
api = Proxy
