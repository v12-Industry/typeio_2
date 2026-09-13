{-# LANGUAGE OverloadedStrings #-}

module App.Middleware
  ( withMiddleware
  ) where

import App.Env (Env (..))
import Config.App (AppConfig (..), webDefaultPath)
import Data.Text (pack)
import Domain.Central.Middleware.IndexRender (renderIndexMiddleware)
import Domain.Central.Responder.Ui.IndexView (handleIndexView)
import Domain.System.Middleware.Logging.Request (requestLogMiddleware)
import Domain.System.Middleware.Logging.Response (responseLogMiddleware)
import Domain.System.Middleware.RequestId (requestIdMiddleware)
import Network.Wai (Middleware)
import Network.Wai.Middleware.Static
  ( CacheContainer
  , CachingStrategy (..)
  , FileMeta (..)
  , Options (..)
  , defaultOptions
  , initCaching
  , staticWithOptions
  )

withMiddleware :: Env -> (Middleware -> IO a) -> IO a
withMiddleware ev k = do
  cc <- initCaching staticCachingStrategy
  k (allMiddleware ev cc)

staticCachingStrategy :: CachingStrategy
staticCachingStrategy = CustomCaching $ \fm ->
  [ ("Cache-Control", "no-cache")
  , ("ETag", fm_etag fm)
  , ("Last-Modified", fm_lastModified fm)
  ]

allMiddleware :: Env -> CacheContainer -> Middleware
allMiddleware ev cc =
  foldr
    (.)
    id
    [ requestIdMiddleware wc
    , requestLogMiddleware wc lg
    , responseLogMiddleware wc lg
    , renderIndexMiddleware dp handleIndexView
    , staticWithOptions defaultOptions {cacheContainer = cc}
    ]
  where
    cf = envConfig ev
    lg = envLogger ev
    wc = webConf cf
    dp = pack (webDefaultPath cf)
