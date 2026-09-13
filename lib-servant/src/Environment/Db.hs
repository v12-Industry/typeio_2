{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Environment.Db where

import Config.Db (DbConfig (..), connStr)
import Control.Monad (void)
import Control.Monad.Cont (ContT (..))
import Control.Monad.IO.Class (liftIO)
import Data.ByteString.Char8 (pack)
import Data.Pool (Pool)
import Data.String (fromString)
import Database.Persist.Postgresql
  ( PostgresConf (..)
  , PostgresConfHooks (..)
  , defaultPostgresConfHooks
  , withPostgresqlPoolWithConf
  )
import Database.Persist.Sql (SqlBackend)
import Database.PostgreSQL.Simple (execute_)
import Logging.Database (runDatabaseLoggingT)

config :: DbConfig -> PostgresConf
config cf =
  PostgresConf
    { pgConnStr = pack $ connStr cf
    , pgPoolStripes = 1
    , pgPoolIdleTimeout = 2000
    , pgPoolSize = poolCount cf
    }

hooks :: DbConfig -> PostgresConfHooks
hooks cf =
  PostgresConfHooks
    { pgConfHooksGetServerVersion = defaultSV
    , pgConfHooksAfterCreate = afterCreate
    }
  where
    defaultSV = pgConfHooksGetServerVersion defaultPostgresConfHooks
    afterCreate conn =
      void
        . execute_ conn
        . (<>) "SET search_path TO "
        . fromString
        . schema
        $ cf

withPool :: DbConfig -> ContT r IO (Pool SqlBackend)
withPool cf = ContT with'
  where
    c = config cf
    h = hooks cf
    with' k =
      runDatabaseLoggingT $
        withPostgresqlPoolWithConf c h $
          liftIO . k
