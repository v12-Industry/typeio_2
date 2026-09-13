{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module App.Link
  ( addWorkLink
  , addWorkSubmitLink
  , createProjectLink
  , createProjectSubmitLink
  , editLink
  , emptyLink
  , graphLink
  , graphLinkFor
  , nodeDescriptionLink
  , nodeDetailLink
  , nodePanelLink
  , nodeRefreshLink
  , nodeResourceLink
  , nodeStatusLink
  , nodeTitleLink
  , projectIndexLink
  , projectLink
  , projectListLink
  , projectStatsLink
  , projectViewLink
  ) where

import App.Api (Api, HxRedirect, api)
import App.Html (HTML)
import App.Params ()
import Config.Visualization (Visualization)
import Data.Int (Int64)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text.Util (intToText)
import qualified Domain.Project.Responder.Api.Node.Get as NodeGet
import GHC.TypeLits (Symbol)
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
  , Put
  , QueryParam'
  , ReqBody
  , Required
  , StdMethod (GET)
  , Strict
  , UVerb
  , WithStatus
  , (:>)
  )
import Servant.Links (HasLink (..), IsElem, Link, safeLink)
import Web.FormUrlEncoded (Form)
import Web.HttpApiData (toUrlPiece)

type ProjectIdParam = QueryParam' '[Required, Strict] "projectId" Int64

type NodeIdParam = QueryParam' '[Required, Strict] "nodeId" Int64

type VisualizationParam =
  QueryParam' '[Optional, Strict] "visualizationMode" Visualization

type ViewParam (n :: Symbol) = QueryParam' '[Optional, Strict] n Double

type HtmlGet = Get '[HTML] (Html ())

type NodeRoute (seg :: Symbol) =
  "ui" :> "project" :> "node" :> seg :> ProjectIdParam :> NodeIdParam :> HtmlGet

type NodeFieldRoute (seg :: Symbol) =
  "ui"
    :> "project"
    :> "node"
    :> seg
    :> ReqBody '[FormUrlEncoded] Form
    :> Put '[HTML] (Html ())

absolute :: Link -> Text
absolute lnk = "/" <> toUrlPiece lnk

link :: (IsElem endpoint Api, HasLink endpoint) => Proxy endpoint -> MkLink endpoint Link
link = safeLink api

emptyLink :: Text
emptyLink =
  absolute (link (Proxy @("ui" :> "central" :> "empty" :> HtmlGet)))

projectIndexLink :: Text
projectIndexLink =
  absolute (link (Proxy @("ui" :> "projects" :> "vw" :> HtmlGet)))

projectListLink :: Text
projectListLink =
  absolute (link (Proxy @("ui" :> "projects" :> "list" :> HtmlGet)))

createProjectLink :: Text
createProjectLink =
  absolute (link (Proxy @("ui" :> "create-project" :> "vw" :> HtmlGet)))

createProjectSubmitLink :: Text
createProjectSubmitLink =
  absolute
    ( link
        ( Proxy
            @( "ui"
                 :> "create-project"
                 :> "submit"
                 :> ReqBody '[FormUrlEncoded] Form
                 :> Post '[HTML] HxRedirect
             )
        )
    )

projectViewLink :: Int64 -> Maybe Int64 -> Maybe Visualization -> Text
projectViewLink pid nid viz =
  absolute (manageVw pid nid viz Nothing Nothing Nothing)
  where
    manageVw =
      link
        ( Proxy
            @( "ui"
                 :> "project"
                 :> "vw"
                 :> ProjectIdParam
                 :> QueryParam' '[Optional, Strict] "nodeId" Int64
                 :> VisualizationParam
                 :> ViewParam "viewX"
                 :> ViewParam "viewY"
                 :> ViewParam "viewScale"
                 :> HtmlGet
             )
        )

projectLink :: Int64 -> Text
projectLink pid = projectViewLink pid Nothing Nothing

graphLinkFor :: Int64 -> Text
graphLinkFor pid = absolute (graph pid Nothing)

graphLink :: Int64 -> Visualization -> Text
graphLink pid viz = absolute (graph pid (Just viz))

graph :: Int64 -> Maybe Visualization -> Link
graph =
  link
    ( Proxy
        @( "ui"
             :> "project"
             :> "graph"
             :> ProjectIdParam
             :> VisualizationParam
             :> HtmlGet
         )
    )

projectStatsLink :: Int64 -> Text
projectStatsLink pid =
  absolute (link (Proxy @("ui" :> "project" :> "stats" :> ProjectIdParam :> HtmlGet)) pid)

nodePanelLink :: Int64 -> Int64 -> Text
nodePanelLink nid pid =
  absolute (link (Proxy @(NodeRoute "panel")) pid nid)

nodeDetailLink :: Int64 -> Int64 -> Text
nodeDetailLink nid pid =
  absolute (link (Proxy @(NodeRoute "detail")) pid nid)

editLink :: Int64 -> Int64 -> Text
editLink nid pid =
  absolute (link (Proxy @(NodeRoute "edit")) pid nid)

nodeRefreshLink :: Int64 -> Int64 -> Int -> Text -> Text
nodeRefreshLink nid pid wrapWidth clientTitle =
  absolute (refresh pid nid clientTitle (Just wrapWidth))
  where
    refresh =
      link
        ( Proxy
            @( "ui"
                 :> "project"
                 :> "node"
                 :> "refresh"
                 :> ProjectIdParam
                 :> NodeIdParam
                 :> QueryParam' '[Required, Strict] "clientTitle" Text
                 :> QueryParam' '[Optional, Strict] "wrapWidth" Int
                 :> UVerb 'GET '[HTML] '[WithStatus 200 (Html ()), WithStatus 204 NoContent]
             )
        )

nodeTitleLink :: Text
nodeTitleLink = absolute (link (Proxy @(NodeFieldRoute "title")))

nodeDescriptionLink :: Text
nodeDescriptionLink = absolute (link (Proxy @(NodeFieldRoute "description")))

nodeStatusLink :: Text
nodeStatusLink = absolute (link (Proxy @(NodeFieldRoute "status")))

addWorkLink :: Int64 -> Text
addWorkLink pid =
  absolute
    ( link
        (Proxy @("ui" :> "project" :> "node" :> "create" :> ProjectIdParam :> HtmlGet))
        pid
    )

addWorkSubmitLink :: Text
addWorkSubmitLink =
  absolute
    ( link
        ( Proxy
            @( "ui"
                 :> "project"
                 :> "node"
                 :> "create"
                 :> ReqBody '[FormUrlEncoded] Form
                 :> Post '[HTML] (Headers '[Header "HX-Trigger" Text] (Html ()))
             )
        )
    )

nodeResourceLink :: Int64 -> Text
nodeResourceLink nid = nodesLink <> "/" <> intToText nid
  where
    nodesLink =
      absolute (link (Proxy @("api" :> "project" :> "nodes" :> Get '[JSON] [NodeGet.Node])))
