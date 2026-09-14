{-# LANGUAGE OverloadedStrings #-}

module Config.Db where

import Common.Validation
  ( ValidationErr
  , errcat
  , isBetween
  , isNotEmpty
  , isThere
  , valRead
  , (.$)
  )
import Control.Monad.Writer (Writer)
import Data.Aeson (ToJSON, object, toJSON, (.=))
import System.Environment (lookupEnv)

keyDb :: String
keyDb = "DB_DATABASE"

keyHost :: String
keyHost = "DB_HOST"

keyPass :: String
keyPass = "DB_PASS"

keyPort :: String
keyPort = "DB_PORT"

keyPoolCount :: String
keyPoolCount = "DB_POOL_COUNT"

keySchema :: String
keySchema = "DB_SCHEMA"

keyUser :: String
keyUser = "DB_USER"

data DbConfig = DbConfig
  { database :: String
  , host :: String
  , password :: String
  , dbPort :: String
  , poolCount :: Int
  , schema :: String
  , user :: String
  }
  deriving (Eq, Read, Show)

data LookupDbConfig = LookupDbConfig
  { database' :: Maybe String
  , host' :: Maybe String
  , password' :: Maybe String
  , port' :: Maybe String
  , poolCount' :: Maybe String
  , schema' :: Maybe String
  , user' :: Maybe String
  }
  deriving Show

loadDbConfig :: IO (Writer [ValidationErr] (Maybe DbConfig))
loadDbConfig = validateConfig <$> lookupConfig

instance ToJSON DbConfig where
  toJSON cfg =
    object
      [ "database" .= database cfg
      , "host" .= host cfg
      , "password" .= password cfg
      , "port" .= dbPort cfg
      , "poolCount" .= poolCount cfg
      , "user" .= user cfg
      ]

connStr :: DbConfig -> String
connStr cfg =
  "host="
    <> host cfg
    <> " dbname="
    <> database cfg
    <> " user="
    <> user cfg
    <> " password="
    <> password cfg
    <> " port="
    <> dbPort cfg
    <> " sslmode=disable"

lookupConfig :: IO LookupDbConfig
lookupConfig =
  LookupDbConfig
    <$> lookupEnv keyDb
    <*> lookupEnv keyHost
    <*> lookupEnv keyPass
    <*> lookupEnv keyPort
    <*> lookupEnv keyPoolCount
    <*> lookupEnv keySchema
    <*> lookupEnv keyUser

validateConfig :: LookupDbConfig -> Writer [ValidationErr] (Maybe DbConfig)
validateConfig c = do
  name <- database' c .$ id >>= isPresent keyDb
  hst <- host' c .$ id >>= isPresent keyHost
  pass <- password' c .$ id >>= isPresent keyPass
  port <- port' c .$ id >>= isPresent keyPort
  plct <-
    poolCount' c .$ id
      >>= isPresent keyPoolCount
      >>= valRead
        (errcat keyPoolCount " must be a valid integer")
      >>= isBetween
        1
        10
        (errcat keyPoolCount " must be between 1 and 10")
  schma <- schema' c .$ id >>= isPresent keySchema
  usr <- user' c .$ id >>= isPresent keyUser
  return $
    DbConfig
      <$> name
      <*> hst
      <*> pass
      <*> port
      <*> plct
      <*> schma
      <*> usr
  where
    er k = errcat k " is missing from environment config"
    isPresent :: String -> Maybe String -> Writer [ValidationErr] (Maybe String)
    isPresent k m = isNotEmpty (er k) m >>= isThere (er k)
