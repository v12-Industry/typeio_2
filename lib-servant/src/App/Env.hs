module App.Env
  ( Env (..)
  , AppM
  , runDb
  , withEnv
  ) where

import Config.App (AppConfig (..))
import Control.Monad.Cont (runContT)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT, asks)
import Database.Persist.Sql (ConnectionPool, SqlBackend, runSqlPool)
import Environment.Db (withPool)
import Servant (Handler)

data Env = Env
  { envConfig :: AppConfig
  , envPool :: ConnectionPool
  }

type AppM = ReaderT Env Handler

runDb :: ReaderT SqlBackend IO a -> AppM a
runDb q = do
  pl <- asks envPool
  liftIO (runSqlPool q pl)

withEnv :: AppConfig -> (Env -> IO a) -> IO a
withEnv cfg k = runContT (withPool (dbConf cfg)) (k . Env cfg)
