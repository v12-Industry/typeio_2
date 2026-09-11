{-# LANGUAGE OverloadedStrings #-}

module Domain.Central.Responder.Ui.IndexView where

import Common.Web.Attributes
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Lucid
import Network.HTTP.Types (status200)
import Network.HTTP.Types.URI (QueryText, queryToQueryText)
import Network.Wai (Application, queryString, responseLBS)

htmxConfig :: Text
htmxConfig =
  "{\"historyCacheSize\": 0, \"responseHandling\": ["
    <> "{\"code\":\"204\",\"swap\":false},"
    <> "{\"code\":\"422\",\"swap\":true,\"error\":true},"
    <> "{\"code\":\"[23]..\",\"swap\":true},"
    <> "{\"code\":\"[45]..\",\"swap\":false,\"error\":true}"
    <> "]}"

queryTextToText :: QueryText -> Maybe Text
queryTextToText [] = Nothing
queryTextToText qs =
  Just $
    foldr
      ( \(k, v) acc ->
          acc <> k <> "=" <> fromMaybe "" v <> "&"
      )
      "?"
      qs

handleIndexView :: Text -> Application
handleIndexView path req res = do
  res $
    responseLBS
      status200
      [("Content-Type", "text/html; charset=utf-8")]
      (renderBS . indexTemplate path $ qs)
  where
    qs =
      queryTextToText
        . queryToQueryText
        . queryString
        $ req

indexTemplate :: Text -> Maybe Text -> Html ()
indexTemplate path qs = html_ $ do
  head_ $ do
    title_ "TypeIO"
    link_ [rel_ "stylesheet", href_ "/static/styles/global.css"]
    link_
      [ rel_ "stylesheet"
      , href_ "/static/styles/material.css"
      ]
    meta_ [name_ "htmx-config", content_ htmxConfig]
    script_ [src_ "/static/script/htmx.js"] empty
    script_ [src_ "https://unpkg.com/hyperscript.org@0.9.14"] empty
  body_ $ do
    div_
      [ id_ "container"
      , hxGet_ lnk
      , hxTrigger_ "load"
      , hxReplaceUrl_ True
      , hxSwap_ "innerHTML"
      ]
      empty
  where
    empty = mempty :: Html ()
    lnk = maybe path (path <>) qs
