{-# LANGUAGE OverloadedStrings #-}

module App.Server
  ( main
  , app
  , server
  ) where

import App.Api (Api, Health (..), api)
import App.Env (AppM, Env (..), runDb, withEnv)
import App.Middleware (withMiddleware)
import Config.App (AppConfig (..), loadConfig)
import Config.Web (WebConfig (..))
import Configuration.Dotenv (defaultConfig, loadFile)
import Control.Exception (SomeException, try)
import Control.Monad.Reader (asks, runReaderT)
import Data.Text (Text, pack)
import Domain.Central.Responder.Api.Seed (seedReferenceData)
import Domain.Central.Responder.Ui.Empty (templateEmpty)
import Domain.System.Responder.Config (ConfigDisplay, configDisplay)
import Lucid (Html)
import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)
import Platform.Build (BuildInfo (..), buildInfo)
import Servant (Handler, Server, ServerT, hoistServer, serve, (:<|>) (..))

server :: ServerT Api AppM
server = healthz :<|> emptyView :<|> seedDatabase :<|> systemConfig

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
