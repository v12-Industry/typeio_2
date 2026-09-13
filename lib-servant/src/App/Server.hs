{-# LANGUAGE OverloadedStrings #-}

module App.Server
  ( main
  , app
  , server
  ) where

import App.Api (Api, CreateProjectUi, Health (..), HxRedirect, ProjectsUi, api)
import App.Env (AppM, Env (..), runDb, withEnv)
import App.Middleware (withMiddleware)
import Config.App (AppConfig (..), loadConfig)
import Config.Web (WebConfig (..))
import Configuration.Dotenv (defaultConfig, loadFile)
import Control.Exception (SomeException, try)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks, runReaderT)
import Data.Text (Text, pack)
import Data.Text.Encoding (decodeUtf8)
import Data.Time (getCurrentTime)
import Database.Persist (entityVal)
import Domain.Central.Responder.Api.Seed (seedReferenceData)
import Domain.Central.Responder.Ui.Empty (templateEmpty)
import qualified Domain.Project.Responder.Ui.ProjectCreate.Submit as Submit
import qualified Domain.Project.Responder.Ui.ProjectCreate.View as CreateView
import qualified Domain.Project.Responder.Ui.ProjectIndex.List as IndexList
import qualified Domain.Project.Responder.Ui.ProjectIndex.View as IndexView
import Domain.System.Responder.Config (ConfigDisplay, configDisplay)
import Lucid (Html)
import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)
import Platform.Build (BuildInfo (..), buildInfo)
import Servant
  ( Handler
  , Server
  , ServerT
  , addHeader
  , hoistServer
  , noHeader
  , serve
  , (:<|>) (..)
  )
import Web.FormUrlEncoded (Form)

server :: ServerT Api AppM
server =
  healthz
    :<|> emptyView
    :<|> seedDatabase
    :<|> systemConfig
    :<|> projectsUi
    :<|> createProjectUi

projectsUi :: ServerT ProjectsUi AppM
projectsUi = projectIndexVw :<|> projectList

projectIndexVw :: AppM (Html ())
projectIndexVw = pure IndexView.projectIndexVwTemplate

projectList :: AppM (Html ())
projectList = do
  ps <- runDb IndexList.queryProjectVw
  pure $ case ps of
    [] -> IndexList.templateEmptyProjects
    _ -> IndexList.templateList (map entityVal ps)

createProjectUi :: ServerT CreateProjectUi AppM
createProjectUi = createProjectVw :<|> submitProject

createProjectVw :: AppM (Html ())
createProjectVw = pure (CreateView.projectCreateVwTemplate CreateView.emptyForm mempty)

submitProject :: Form -> AppM HxRedirect
submitProject f = do
  let form = Submit.formToAddProjectForm f
  now <- liftIO getCurrentTime
  rslt <- runDb (Submit.createProject form now)
  pure $ case rslt of
    Right _ -> addHeader (decodeUtf8 (snd Submit.redirectHeader)) mempty
    Left (Submit.FormValidationFail es) ->
      noHeader (CreateView.projectCreateVwTemplate form es)
    Left _ -> noHeader (CreateView.projectCreateVwTemplate form ["Could not create the project"])

healthz :: AppM Health
healthz =
  pure
    Health
      { healthStatus = "ok"
      , healthCommit = pack (commit buildInfo)
      }

emptyView :: AppM (Html ())
emptyView = pure templateEmpty

seedDatabase :: AppM Text
seedDatabase = do
  runDb seedReferenceData
  pure "Database seeded successfully"

systemConfig :: AppM ConfigDisplay
systemConfig = asks (configDisplay . envConfig)

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
