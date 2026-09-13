{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

module Logging.Core where

import Data.Aeson (ToJSON, encode, object, toJSON, (.=))
import Data.Char (toLower)
import System.Log.FastLogger (TimedFastLogger, toLogStr)

type LogSource = String

data LogLevel = Debug | Info | Warning | Error
  deriving (Show, Eq)

instance ToJSON LogLevel where
  toJSON lvl = toJSON $ map toLower (show lvl)

newtype EntryLog = EntryLog
  { runEntryLog ::
      forall a.
      ToJSON a =>
      LogSource ->
      LogLevel ->
      a ->
      IO ()
  }

data JsonLog a = JsonLog
  { message :: a
  , level :: LogLevel
  , source :: String
  , timestamp :: String
  }
  deriving Show

instance ToJSON a => ToJSON (JsonLog a) where
  toJSON (JsonLog msg lvl src ts) =
    object
      [ "message" .= msg
      , "level" .= lvl
      , "source" .= src
      , "timestamp" .= ts
      ]

toEntryLog :: TimedFastLogger -> EntryLog
toEntryLog logger = EntryLog $ \src lvl msg -> logger $ \time ->
  let msg' =
        encode $
          JsonLog
            { message = msg
            , level = lvl
            , source = src
            , timestamp = show time
            }
   in toLogStr msg' <> "\n"
