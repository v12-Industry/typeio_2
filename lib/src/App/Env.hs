module App.Env
  ( Env (..)
  , AppM
  , runDb
  , withEnv
  ) where

import Config.App (AppConfig (..))
import Control.Monad.Cont (ContT (..), runContT)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT, asks)
import Database.Persist.Sql (ConnectionPool, SqlBackend, runSqlPool)
import Environment.Db (withPool)
import Environment.Logging (withLogger)
import Logging.Core (EntryLog)
import Servant (Handler)

data Env = Env
  { envConfig :: AppConfig
  , envLogger :: EntryLog
  , envPool :: ConnectionPool
  }

type AppM = ReaderT Env Handler

runDb :: ReaderT SqlBackend IO a -> AppM a
runDb q = do
  pl <- asks envPool
  liftIO (runSqlPool q pl)

withEnv :: AppConfig -> (Env -> IO a) -> IO a
withEnv cfg =
  runContT $
    Env cfg
      <$> withLogger
      <*> withPool (dbConf cfg)
