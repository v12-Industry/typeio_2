{-# LANGUAGE OverloadedStrings #-}

module Platform.Web.Middleware where

import Config.App (AppConfig (..))
import Container.Root (RootContainer (..))
import Domain.Central.Container (CentralContainer (..))
import Domain.Central.Middleware.IndexRender (renderIndexMiddleware)
import Domain.System.Middleware.Logging.Request (requestLogMiddleware)
import Domain.System.Middleware.Logging.Response (responseLogMiddleware)
import Domain.System.Middleware.RequestId (requestIdMiddleware)
import Environment.Env (Env (..))
import Network.HTTP.Types (RequestHeaders)
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

withMiddleware :: Env -> RootContainer -> (Middleware -> IO a) -> IO a
withMiddleware ev ct k = do
  cc <- initCaching staticCachingStrategy
  k (allMiddleware ev ct cc)

staticCachingStrategy :: CachingStrategy
staticCachingStrategy = CustomCaching staticCacheHeaders

staticCacheHeaders :: FileMeta -> RequestHeaders
staticCacheHeaders fm =
  [ ("Cache-Control", "no-cache")
  , ("ETag", fm_etag fm)
  , ("Last-Modified", fm_lastModified fm)
  ]

allMiddleware :: Env -> RootContainer -> CacheContainer -> Middleware
allMiddleware ev ct cc =
  let m =
        [ requestIdMiddleware wc
        , requestLogMiddleware wc lg
        , responseLogMiddleware wc lg
        , renderIndexMiddleware . centralUiContainer . central $ ct
        , staticWithOptions defaultOptions {cacheContainer = cc}
        ]
   in foldr1 (.) m
  where
    cf = appConf ev
    lg = logger ev
    wc = webConf cf
