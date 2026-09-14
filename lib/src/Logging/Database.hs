{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}

module Logging.Database where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.IO.Unlift (MonadUnliftIO)
import Control.Monad.Logger
  ( LogLevel
  , LogSource
  , MonadLogger
  , MonadLoggerIO
  , askLoggerIO
  , monadLoggerLog
  )
import Control.Monad.Reader
  ( MonadReader
  , ReaderT
  , ask
  , local
  , reader
  , runReaderT
  )
import Data.Aeson (ToJSON, encode, object, toJSON, (.=))
import Data.ByteString.Char8 (ByteString, unpack)
import Data.Char (toLower)
import Data.Time (UTCTime, getCurrentTime)
import System.Log.FastLogger
  ( LoggerSet
  , ToLogStr (toLogStr)
  , defaultBufSize
  , fromLogStr
  , newStdoutLoggerSet
  , pushLogStr
  )

data DatabaseLog = DatabaseLog
  { message :: QueryMessage
  , level :: LogLevel
  , source :: LogSource
  , timestamp :: UTCTime
  }
  deriving Show

newtype DatabaseLoggingT m a = DatabaseLoggingT
  { unDatabaseLoggingT :: ReaderT LoggerSet m a
  }
  deriving
    ( Functor
    , Applicative
    , Monad
    , MonadIO
    , MonadUnliftIO
    )

newtype QueryMessage = QueryMessage
  { query :: ByteString
  }
  deriving Show

databaseLog ::
  ToLogStr a =>
  LogSource ->
  LogLevel ->
  a ->
  UTCTime ->
  DatabaseLog
databaseLog src lvl msg t =
  DatabaseLog
    { message = queryMessage msg
    , level = lvl
    , source = src
    , timestamp = t
    }

queryMessage :: ToLogStr a => a -> QueryMessage
queryMessage = QueryMessage . (fromLogStr . toLogStr)

runDatabaseLoggingT :: MonadIO m => DatabaseLoggingT m a -> m a
runDatabaseLoggingT action = do
  loggerSet <- liftIO $ newStdoutLoggerSet defaultBufSize
  runReaderT (unDatabaseLoggingT action) loggerSet

instance ToJSON DatabaseLog where
  toJSON (DatabaseLog msg lvl src ts) =
    object
      [ "message" .= msg
      , "level" .= map toLower (drop 5 . show $ lvl)
      , "source" .= src
      , "timestamp" .= ts
      ]

instance MonadIO m => MonadLogger (DatabaseLoggingT m) where
  monadLoggerLog _ src lvl msg = do
    loggerSet <- ask
    t <- liftIO getCurrentTime
    let js = databaseLog src lvl msg t
        ts = toLogStr . encode $ js
    liftIO $ pushLogStr loggerSet ts

instance MonadIO m => MonadLoggerIO (DatabaseLoggingT m) where
  askLoggerIO = do
    loggerSet <- ask
    return $ \_ src lvl msg -> do
      t <- getCurrentTime
      let js = databaseLog src lvl msg t
          ts = toLogStr . encode $ js
      pushLogStr loggerSet ts

instance Monad m => MonadReader LoggerSet (DatabaseLoggingT m) where
  ask = DatabaseLoggingT ask
  local f (DatabaseLoggingT action) = DatabaseLoggingT $ local f action
  reader f = DatabaseLoggingT $ reader f

instance ToJSON QueryMessage where
  toJSON (QueryMessage q) = object ["query" .= unpack q]
