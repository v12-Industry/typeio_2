{-# LANGUAGE OverloadedStrings #-}

module Domain.System.Middleware.Logging.Response where

import Config.Web (WebConfig (..))
import Data.Aeson (ToJSON (..), object, (.=))
import Data.ByteString.Char8 (ByteString, unpack)
import Data.HashMap.Strict (HashMap)
import Domain.System.Middleware.Logging.Common (hashMapHeaders)
import Logging.Core
  ( EntryLog
  , LogLevel (..)
  , runEntryLog
  )
import Network.HTTP.Types (HeaderName, statusCode)
import Network.Wai
  ( Middleware
  , Request
  , Response
  , requestHeaders
  , responseHeaders
  , responseStatus
  )

data ResponseLog = ResponseLog
  { headers :: HashMap String String
  , requestId :: Maybe ByteString
  , status :: Int
  }
  deriving Show

instance ToJSON ResponseLog where
  toJSON (ResponseLog h r s) =
    object
      [ "headers" .= h
      , "requestId" .= fmap unpack r
      , "status" .= s
      ]

fromTraffic :: HeaderName -> Request -> Response -> ResponseLog
fromTraffic hn req resp =
  ResponseLog
    { headers = hashMapHeaders . responseHeaders $ resp
    , requestId = lookup hn (requestHeaders req)
    , status = statusCode . responseStatus $ resp
    }

responseLogMiddleware :: WebConfig -> EntryLog -> Middleware
responseLogMiddleware cf lg ap req respond = do
  ap req $ \resp -> do
    let hn = requestIdHeader cf
        logEntry = fromTraffic hn req resp
    runEntryLog lg "ResponseLog" Info logEntry
    respond resp
