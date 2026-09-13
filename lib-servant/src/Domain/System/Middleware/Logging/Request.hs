{-# LANGUAGE OverloadedStrings #-}

module Domain.System.Middleware.Logging.Request where

import Config.Web (WebConfig (..))
import Data.Aeson (ToJSON (..), object, (.=))
import Data.ByteString.Char8 (ByteString, unpack)
import Data.HashMap.Strict (HashMap)
import Domain.System.Middleware.Logging.Common (hashMapHeaders)
import Logging.Core (EntryLog, LogLevel (..), runEntryLog)
import Network.HTTP.Types (HeaderName)
import Network.Wai
  ( Middleware
  , Request
  , pathInfo
  , requestHeaders
  , requestMethod
  )

data RequestLog = RequestLog
  { method :: String
  , path :: String
  , headers :: HashMap String String
  , requestId :: Maybe ByteString
  }

instance ToJSON RequestLog where
  toJSON (RequestLog m p h r) =
    object
      [ "method" .= m
      , "path" .= p
      , "headers" .= h
      , "requestId" .= fmap unpack r
      ]

fromRequest :: HeaderName -> Request -> RequestLog
fromRequest hn req =
  RequestLog
    { method = show $ requestMethod req
    , path = show $ pathInfo req
    , headers = hashMapHeaders . requestHeaders $ req
    , requestId = lookup hn (requestHeaders req)
    }

requestLogMiddleware :: WebConfig -> EntryLog -> Middleware
requestLogMiddleware wc lg ap req respond = do
  let hn = requestIdHeader wc
      logEntry = fromRequest hn req
  runEntryLog lg "Web" Info logEntry
  ap req respond
