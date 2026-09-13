{-# LANGUAGE OverloadedStrings #-}

module App.Server
  ( main
  , app
  , server
  ) where

import App.Api (Api, Health (..), ManageProjectUi, api)
import App.Env (AppM, Env (..), runDb, withEnv)
import App.Middleware (withMiddleware)
import App.Params ()
import Config.App (AppConfig (..), loadConfig)
import Config.Visualization (Visualization, defaultVisualization)
import Config.Web (WebConfig (..))
import Configuration.Dotenv (defaultConfig, loadFile)
import Control.Exception (SomeException, try)
import Control.Monad.Error.Class (throwError)
import Control.Monad.Reader (asks, runReaderT)
import Data.Aeson (encode, object, (.=))
import Data.Int (Int64)
import Data.Maybe (fromMaybe)
import Data.Text (Text, pack)
import Data.Text.Util (intToText)
import Database.Persist (entityKey)
import Database.Persist.Sql (fromSqlKey)
import Domain.Central.Responder.Api.Seed (seedReferenceData)
import Domain.Central.Responder.Ui.Empty (templateEmpty)
import qualified Domain.Project.Responder.Ui.ProjectManage.View as ManageView
import qualified Domain.Project.Visualization.Common as Viz
import Domain.Project.Visualization.Dispatch (renderFor)
import Domain.System.Responder.Config (ConfigDisplay, configDisplay)
import Lucid (Html)
import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)
import Platform.Build (BuildInfo (..), buildInfo)
import Servant
  ( Handler
  , Server
  , ServerT
  , err404
  , errBody
  , hoistServer
  , serve
  , (:<|>) (..)
  )

server :: ServerT Api AppM
server =
  healthz
    :<|> emptyView
    :<|> seedDatabase
    :<|> systemConfig
    :<|> manageProjectUi

manageProjectUi :: ServerT ManageProjectUi AppM
manageProjectUi = manageProjectVw :<|> projectGraph

manageProjectVw ::
  Int64 ->
  Maybe Int64 ->
  Maybe Visualization ->
  Maybe Double ->
  Maybe Double ->
  Maybe Double ->
  AppM (Html ())
manageProjectVw pid nid mviz vx vy vk =
  pure $
    ManageView.templateProject
      ManageView.ManageProjectPayload
        { ManageView.payloadNodeId = nid
        , ManageView.payloadProjectId = pid
        , ManageView.payloadVisualization = viz
        , ManageView.payloadView = ManageView.ViewTransform <$> vx <*> vy <*> vk
        , ManageView.payloadViewBase = viewBase pid nid viz
        }
  where
    viz = fromMaybe defaultVisualization mviz

-- Rebuilt from the parameters the route actually parsed rather than from
-- the raw query string, so the base the viewport appends to is canonical
-- whatever the client sent.
viewBase :: Int64 -> Maybe Int64 -> Visualization -> Text
viewBase pid nid viz =
  "/ui/project/vw?projectId="
    <> intToText pid
    <> maybe "" (\n -> "&nodeId=" <> intToText n) nid
    <> "&visualizationMode="
    <> pack (show viz)

projectGraph :: Int64 -> Maybe Visualization -> AppM (Html ())
projectGraph pid mviz = do
  ns <- runDb (Viz.queryNodes pid)
  case ns of
    [] -> throwError err404 {errBody = encode (object ["error" .= noNodes])}
    _ -> do
      ds <- runDb (Viz.queryDependencies (map (fromSqlKey . entityKey) ns))
      pure $ renderFor (fromMaybe defaultVisualization mviz) pid ns ds
  where
    noNodes = "No nodes found for the project" :: Text

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
