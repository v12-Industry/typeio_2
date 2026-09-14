{-# LANGUAGE OverloadedStrings #-}

module Common.Web.Template.MainHeader where

import App.Link (projectIndexLink)
import Common.Web.Attributes
import Data.Text (Text)
import Lucid

templateNavHeader :: Text -> Html ()
templateNavHeader current =
  templateNavHeaderWith current (div_ [class_ "dot"] mempty)

templateNavHeaderWith :: Text -> Html () -> Html ()
templateNavHeaderWith current trailing = do
  header_ [class_ "nav"] $ do
    h1_
      [ class_ "logo"
      , hxGet_ projectIndexLink
      , hxPushUrl_ True
      , hxSwap_ "innerHTML"
      , hxTarget_ "#container"
      ]
      "textio"
    h2_ [] (toHtml current)
    trailing
