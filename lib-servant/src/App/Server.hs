{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module App.Server
  ( main
  , app
  , server
  ) where

import App.Api (Api, Health (..), api)
import App.Env (AppM, Env, withEnv)
import Config.App (AppConfig (..), loadConfig)
import Config.Web (WebConfig (..))
import Configuration.Dotenv (defaultConfig, loadFile)
import Control.Exception (SomeException, try)
import Control.Monad.Reader (runReaderT)
import Data.Text (pack)
import Lucid
import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)
import Platform.Build (BuildInfo (..), buildInfo)
import Servant (Handler, Server, ServerT, hoistServer, serve, (:<|>) (..))

server :: ServerT Api AppM
server = healthz :<|> landing

healthz :: AppM Health
healthz =
  pure
    Health
      { healthStatus = "ok"
      , healthCommit = pack (commit buildInfo)
      }

landing :: AppM (Html ())
landing = pure $ html_ $ do
  head_ $ title_ "TypeIO"
  body_ $ h1_ "TypeIO"

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
  withEnv cfg $ run (port (webConf cfg)) . app

loadDotEnv :: IO ()
loadDotEnv = do
  _ <- try (loadFile defaultConfig) :: IO (Either SomeException ())
  return ()
