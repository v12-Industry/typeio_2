{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module App.Server
  ( main
  , app
  , server
  ) where

import App.Api (Api, CreatedNode (..), Health (..), ProjectApi, api)
import App.Env (AppM, Env (..), runDb, withEnv)
import App.Middleware (withMiddleware)
import Config.App (AppConfig (..), loadConfig)
import Config.Web (WebConfig (..))
import Configuration.Dotenv (defaultConfig, loadFile)
import Control.Exception (SomeException, try)
import Control.Monad.Error.Class (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (asks, runReaderT)
import Data.Aeson (encode, object, (.=))
import Data.Text (Text, pack)
import Data.Text.Util (intToText)
import Data.Time (getCurrentTime)
import Database.Persist (Entity (..))
import Database.Persist.Sql (fromSqlKey)
import Domain.Central.Responder.Api.Seed (seedReferenceData)
import Domain.Central.Responder.Ui.Empty (templateEmpty)
import qualified Domain.Project.Responder.Api.Node.Get as NodeGet
import qualified Domain.Project.Responder.Api.Node.Post as NodePost
import qualified Domain.Project.Responder.Api.NodeStatus.Get as NodeStatusGet
import qualified Domain.Project.Responder.Api.NodeType.Get as NodeTypeGet
import qualified Domain.Project.Responder.Api.Project.Get as ProjectGet
import Domain.System.Responder.Config (ConfigDisplay, configDisplay)
import Lucid (Html)
import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)
import Platform.Build (BuildInfo (..), buildInfo)
import Servant
  ( Handler
  , Header
  , Headers
  , Server
  , ServerT
  , addHeader
  , err404
  , err422
  , err500
  , errBody
  , hoistServer
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
    :<|> projectApi

projectApi :: ServerT ProjectApi AppM
projectApi =
  getNodes
    :<|> postNode
    :<|> getNodeStatuses
    :<|> getNodeTypes
    :<|> getProjects

getNodes :: AppM [NodeGet.Node]
getNodes = runDb NodeGet.listNodes

getNodeStatuses :: AppM [NodeStatusGet.NodeStatus]
getNodeStatuses = runDb NodeStatusGet.listNodeStatuses

getNodeTypes :: AppM [NodeTypeGet.NodeType]
getNodeTypes = runDb NodeTypeGet.listNodeTypes

getProjects :: AppM [ProjectGet.Project]
getProjects = runDb ProjectGet.listProjects

postNode ::
  Form ->
  AppM (Headers '[Header "Location" Text] CreatedNode)
postNode form = do
  now <- liftIO getCurrentTime
  rslt <- runDb (NodePost.createNode (NodePost.formToPostNodeForm form) now)
  case rslt of
    Left (NodePost.FailValidation es) -> throwError err422 {errBody = errJson es}
    Left NodePost.ProjectNotFound ->
      throwError err404 {errBody = errJson ["Project not found" :: Text]}
    Left NodePost.MissingStatus -> throwError err500 {errBody = serverErr}
    Left NodePost.MissingType -> throwError err500 {errBody = serverErr}
    Right (Entity ky _) ->
      let nid = fromSqlKey ky
       in pure $
            addHeader
              ("/api/project/nodes/" <> intToText nid)
              (CreatedNode nid)
  where
    errJson es = encode (object ["error" .= es])
    serverErr = errJson ["Internal server error" :: Text]

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
