{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module App.Server
  ( main
  , app
  , server
  ) where

import App.Api
  ( AddWorkUi
  , Api
  , CreateProjectUi
  , ManageProjectUi
  , NodeFieldUi
  , NodeUi
  , ProjectApi
  , ProjectsUi
  , api
  )
import App.Env (AppM, Env (..), withEnv)
import App.Middleware (withMiddleware)
import App.Params ()
import Config.App (AppConfig (..), loadConfig)
import Config.Web (WebConfig (..))
import Configuration.Dotenv (defaultConfig, loadFile)
import Control.Exception (SomeException, try)
import Control.Monad.Reader (runReaderT)
import qualified Domain.Central.Responder.Api.Seed as Seed
import qualified Domain.Central.Responder.Ui.Empty as Empty
import qualified Domain.Project.Responder.Api.Node.Get as NodeGet
import qualified Domain.Project.Responder.Api.Node.Post as NodePost
import qualified Domain.Project.Responder.Api.NodeStatus.Get as NodeStatusGet
import qualified Domain.Project.Responder.Api.NodeType.Get as NodeTypeGet
import qualified Domain.Project.Responder.Api.Project.Get as ProjectGet
import qualified Domain.Project.Responder.Ui.ProjectCreate.Submit as Submit
import qualified Domain.Project.Responder.Ui.ProjectCreate.View as CreateView
import qualified Domain.Project.Responder.Ui.ProjectIndex.List as IndexList
import qualified Domain.Project.Responder.Ui.ProjectIndex.View as IndexView
import qualified Domain.Project.Responder.Ui.ProjectManage.Node as NodePanel
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Create as AddWork
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Description as NodeDescription
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Detail as NodeDetail
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Edit as NodeEdit
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Refresh as NodeRefresh
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Status as NodeStatus
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Title as NodeTitle
import qualified Domain.Project.Responder.Ui.ProjectManage.Stats as ProjectStats
import qualified Domain.Project.Responder.Ui.ProjectManage.View as ManageView
import qualified Domain.Project.Visualization.Dispatch as Graph
import qualified Domain.System.Responder.Config as SystemConfig
import qualified Domain.System.Responder.Health as Health
import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)
import Servant (Handler, Server, ServerT, hoistServer, serve, (:<|>) (..))

server :: ServerT Api AppM
server =
  Health.handler
    :<|> Empty.handler
    :<|> Seed.handler
    :<|> SystemConfig.handler
    :<|> projectApi
    :<|> projectsUi
    :<|> createProjectUi
    :<|> manageProjectUi

projectApi :: ServerT ProjectApi AppM
projectApi =
  NodeGet.handler
    :<|> NodePost.handler
    :<|> NodeStatusGet.handler
    :<|> NodeTypeGet.handler
    :<|> ProjectGet.handler

projectsUi :: ServerT ProjectsUi AppM
projectsUi = IndexView.handler :<|> IndexList.handler

createProjectUi :: ServerT CreateProjectUi AppM
createProjectUi = CreateView.handler :<|> Submit.handler

manageProjectUi :: ServerT ManageProjectUi AppM
manageProjectUi =
  ManageView.handler
    :<|> Graph.handler
    :<|> (nodeUi :<|> nodeFieldUi :<|> addWorkUi)
    :<|> ProjectStats.handler

nodeUi :: ServerT NodeUi AppM
nodeUi =
  NodePanel.handler
    :<|> NodeDetail.handler
    :<|> NodeEdit.handler
    :<|> NodeRefresh.handler

nodeFieldUi :: ServerT NodeFieldUi AppM
nodeFieldUi =
  NodeTitle.handler
    :<|> NodeDescription.handler
    :<|> NodeStatus.handler

addWorkUi :: ServerT AddWorkUi AppM
addWorkUi = AddWork.handler :<|> AddWork.submitHandler

hoisted :: Env -> Server Api
hoisted ev = hoistServer api (nt ev) server

nt :: Env -> AppM a -> Handler a
nt ev a = runReaderT a ev

app :: Env -> Application
app = serve api . hoisted

main :: IO ()
main = do
  loadDotEnv
  cfg <- loadConfig
  withEnv cfg $ \ev ->
    withMiddleware ev $ \md ->
      run (port (webConf cfg)) (md (app ev))

loadDotEnv :: IO ()
loadDotEnv = do
  _ <- try (loadFile defaultConfig) :: IO (Either SomeException ())
  return ()
