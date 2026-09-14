{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.SaveState
  ( templateSaveState
  ) where

import Common.Web.Attributes (h_)
import Data.Text (Text)
import Lucid

templateSaveState :: Html ()
templateSaveState =
  div_ [id_ "save-state", h_ saveStateScript] $ do
    span_ [class_ "save-state-idle"] $ span_ [class_ "dot"] mempty
    span_ [class_ "save-state-pending"] $ do
      span_ [class_ "loading"] mempty
      span_ [] "Saving..."
    span_ [class_ "save-state-saved"] $ do
      i_ [class_ "material-icons"] "done"
      span_ [] "Saved"

saveStateScript :: Text
saveStateScript =
  "on htmx:beforeRequest from body "
    <> "if the event's detail's elt matches <[data-saves]/> "
    <> "remove .is-saved from me then add .is-saving to me "
    <> "end "
    <> "on htmx:afterRequest from body "
    <> "if the event's detail's elt matches <[data-saves]/> "
    <> "remove .is-saving from me "
    <> "then if the event's detail's successful add .is-saved to me end "
    <> "end"
