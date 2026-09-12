{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module Platform.Web.Router where

import Config.App (webDefaultPath)
import Container.Root (RootContainer (..))
import Control.Applicative ((<|>))
import Data.HashTree
import Data.Maybe (fromMaybe)
import Data.Text (Text, pack)
import qualified Domain.Central.Container as CentralContainer
import Domain.Central.Responder.Api.Container (CentralApiContainer (..))
import qualified Domain.Central.Responder.Ui.Container as CentralUi
import qualified Domain.Project.Container as ProjectContainer
import qualified Domain.Project.Responder.Api.Container as ProjectApi
import qualified Domain.Project.Responder.Ui.Container as ProjectUi
import qualified Domain.System.Container as SystemContainer
import qualified Domain.System.Responder.Container as SystemResponder
import Network.HTTP.Types (Method, status404)
import Network.Wai

type RouteTree = HashTree Text MethodTree

type MethodTree =
  HashTree Method ((Response -> IO ResponseReceived) -> IO ResponseReceived)

routes :: RouteTree
routes = emptyT

methods :: MethodTree
methods = emptyT

only ::
  Method ->
  ((Response -> IO ResponseReceived) -> IO ResponseReceived) ->
  MethodTree
only m r = methods <+> m -| r

routeRequest ::
  RootContainer ->
  Request ->
  ((Response -> IO ResponseReceived) -> IO ResponseReceived)
routeRequest ctn req =
  fromMaybe (notFound req) $
    findPath pth (rootTree ctn req)
      >>= findPath [mth]
  where
    pth = pathInfo req <|> [""]
    mth = requestMethod req

notFound :: Application
notFound _ res = res $ responseLBS status404 [] "Not Found"

rootTree :: RootContainer -> Request -> RouteTree
rootTree ctn req =
  emptyT
    <+> ""
    -| only "GET" (index ctn dp req)
    <+> "api"
    -< apiTree ctn req
    <+> "ui"
    -< uiTree ctn req
  where
    dp = pack . webDefaultPath . appConfig $ ctn

apiTree :: RootContainer -> Request -> RouteTree
apiTree ctn req =
  emptyT
    <+> "central"
    -< centralApiTree ctrCtn
    <+> "project"
    -< projectApiTree prjCtn req
    <+> "system"
    -< systemApiTree sysCtn req
  where
    ctrCtn = CentralContainer.centralApiContainer . central $ ctn
    prjCtn = ProjectContainer.projectApiContainer' . project $ ctn
    sysCtn = SystemContainer.responder . system $ ctn

centralApiTree :: CentralApiContainer -> RouteTree
centralApiTree ctn =
  emptyT
    <+> "seed-database"
    -| only "POST" (apiSeedDatabase ctn)

projectApiTree :: ProjectApi.Container -> Request -> RouteTree
projectApiTree ctn req =
  emptyT
    <+> "nodes"
    -| ( methods
           <+> "GET"
           -| ProjectApi.getNodes ctn
           <+> "POST"
           -| ProjectApi.postNode ctn req
       )
    <+> "node-types"
    -| only "GET" (ProjectApi.getNodeTypes ctn)
    <+> "node-statuses"
    -| only "GET" (ProjectApi.getNodeStatuses ctn)
    <+> "projects"
    -| only "GET" (ProjectApi.getProjects ctn)

systemApiTree :: SystemResponder.Container -> Request -> RouteTree
systemApiTree ctn _ =
  emptyT
    <+> "config"
    -| only "GET" (SystemResponder.getConfig ctn)

uiTree :: RootContainer -> Request -> RouteTree
uiTree ctn req =
  routes
    <+> "central"
    -< centralUiTree ctlCtn
    <+> "create-project"
    -< addProjectUiTree puiCtn req
    <+> "project"
    -< manageProjectUiTree puiCtn req
    <+> "projects"
    -< projectIndexUiTree puiCtn req
  where
    puiCtn = ProjectContainer.projectUiContainer' . project $ ctn
    ctlCtn = CentralContainer.centralUiContainer . central $ ctn

centralUiTree :: CentralUi.Container -> RouteTree
centralUiTree ct =
  routes
    <+> "empty"
    -| only "GET" (CentralUi.emptyView ct)

projectIndexUiTree :: ProjectUi.Container -> Request -> RouteTree
projectIndexUiTree ctn _ =
  emptyT
    <+> "vw"
    -| only "GET" (ProjectUi.projectIndexVw ctn)
    <+> "list"
    -| only "GET" (ProjectUi.projectList ctn)

addProjectUiTree :: ProjectUi.Container -> Request -> RouteTree
addProjectUiTree ctn req =
  emptyT
    <+> "vw"
    -| only "GET" (ProjectUi.createProjectVw ctn)
    <+> "submit"
    -| only "POST" (ProjectUi.submitProject ctn req)

manageProjectUiTree :: ProjectUi.Container -> Request -> RouteTree
manageProjectUiTree ctn req =
  emptyT
    <+> "vw"
    -| only "GET" (ProjectUi.manageProjectVw ctn req)
    <+> "graph"
    -| only "GET" (ProjectUi.getProjectGraph ctn req)
    <+> "stats"
    -| only "GET" (ProjectUi.getProjectStats ctn req)
    <+> "node"
    -< ( routes
           <+> "panel"
           -| only "GET" (ProjectUi.getNodePanel ctn req)
           <+> "create"
           -| ( methods
                  <+> "GET"
                  -| ProjectUi.getAddWork ctn req
                  <+> "POST"
                  -| ProjectUi.postWork ctn req
              )
           <+> "edit"
           -| only "GET" (ProjectUi.getNodeEdit ctn req)
           <+> "detail"
           -| only "GET" (ProjectUi.getNodeDetail ctn req)
           <+> "description"
           -| only "PUT" (ProjectUi.putNodeDescription ctn req)
           <+> "refresh"
           -| only "GET" (ProjectUi.getNodeRefresh ctn req)
           <+> "status"
           -| only "PUT" (ProjectUi.putNodeStatus ctn req)
           <+> "title"
           -| only "PUT" (ProjectUi.putNodeTitle ctn req)
       )

index ::
  RootContainer ->
  Text ->
  Application
index = CentralUi.indexView . CentralContainer.centralUiContainer . central
