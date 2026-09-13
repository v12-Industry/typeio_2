{-# LANGUAGE OverloadedStrings #-}

module Domain.Central.Responder.Ui.Empty where

import App.Env (AppM)
import Lucid
import Network.HTTP.Types (status200)
import Network.Wai (Response, ResponseReceived, responseLBS)

handleGetEmpty :: (Response -> IO ResponseReceived) -> IO ResponseReceived
handleGetEmpty res = do
  res $
    responseLBS
      status200
      [("Content-Type", "text/html; charset=utf-8")]
      (renderBS templateEmpty)

templateEmpty :: Html ()
templateEmpty = mempty

handler :: AppM (Html ())
handler = pure templateEmpty
