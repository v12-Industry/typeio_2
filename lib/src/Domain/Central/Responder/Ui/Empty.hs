{-# LANGUAGE OverloadedStrings #-}

module Domain.Central.Responder.Ui.Empty where

import App.Env (AppM)
import Lucid

templateEmpty :: Html ()
templateEmpty = mempty

handler :: AppM (Html ())
handler = pure templateEmpty
