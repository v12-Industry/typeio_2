{-# LANGUAGE OverloadedStrings #-}

module Domain.Central.Middleware.IndexRender
  ( IndexApp
  , renderIndexMiddleware
  , hasHexHeader
  ) where

import Data.ByteString.Char8 (pack, unpack)
import Data.CaseInsensitive (mk)
import Data.List (intercalate)
import Data.Text (Text)
import qualified Data.Text as T (pack, unpack)
import Network.HTTP.Types (RequestHeaders)
import Network.Wai (Application, Middleware, pathInfo, requestHeaders)

type IndexApp = Text -> Application

hasHexHeader :: String -> RequestHeaders -> Bool
hasHexHeader headerName headers =
  case lookup (mk . pack $ headerName) headers of
    Just value -> unpack value == "true"
    Nothing -> False

renderIndexMiddleware :: Text -> IndexApp -> Middleware
renderIndexMiddleware defaultPath indexApp app req respond =
  case pathInfo req of
    [] -> indexApp defaultPath req respond
    path
      | isView path && (not isHx || isHxRestore) ->
          indexApp (toPathText path) req respond
    _ -> app req respond
  where
    hs = requestHeaders req
    isHx = hasHexHeader "HX-Request" hs
    isHxRestore = hasHexHeader "HX-History-Restore-Request" hs
    isView ("ui" : ps) = "vw" `elem` ps
    isView _ = False
    toPathText = T.pack . ('/' :) . intercalate "/" . map T.unpack
