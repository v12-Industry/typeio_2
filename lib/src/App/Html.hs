{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}

module App.Html
  ( HTML
  ) where

import Lucid (Html, renderBS)
import qualified Network.HTTP.Media as M
import Servant.API (Accept (..), MimeRender (..))

data HTML

instance Accept HTML where
  contentType _ = "text" M.// "html" M./: ("charset", "utf-8")

instance MimeRender HTML (Html ()) where
  mimeRender _ = renderBS
