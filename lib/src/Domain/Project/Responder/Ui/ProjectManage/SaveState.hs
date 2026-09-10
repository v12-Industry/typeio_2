{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.SaveState
  ( saveStateIndicator
  , templateSaveState
  , templateSaveStateIdle
  , templateSaveStateSaved
  ) where

import Common.Web.Attributes (hxSwapOob_)
import Data.Text (Text)
import Lucid

saveStateIndicator :: Text
saveStateIndicator = "#save-state"

templateSaveState :: Html ()
templateSaveState =
  div_ [id_ "save-state"] $ do
    span_ [class_ "save-state-pending"] $ do
      span_ [class_ "loading"] mempty
      span_ [] "Saving..."
    span_ [id_ "save-state-result", class_ "save-state-idle"] templateIdleDot

templateSaveStateSaved :: Html ()
templateSaveStateSaved =
  span_
    [ id_ "save-state-result"
    , class_ "save-state-saved"
    , hxSwapOob_ "true"
    ]
    $ do
      i_ [class_ "material-icons"] "done"
      span_ [] "Saved"

templateSaveStateIdle :: Html ()
templateSaveStateIdle =
  span_
    [ id_ "save-state-result"
    , class_ "save-state-idle"
    , hxSwapOob_ "true"
    ]
    templateIdleDot

templateIdleDot :: Html ()
templateIdleDot = span_ [class_ "dot"] mempty
