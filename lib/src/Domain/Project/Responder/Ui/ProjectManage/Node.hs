{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Node where

import App.Env (AppM)
import App.Link
import Common.Web.Attributes
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Util (intToText)
import Lucid

templateNodePanel :: Int64 -> Int64 -> Html ()
templateNodePanel nid pid = do
  div_
    [ class_ "panel-actions"
    , dataNodeId_ . intToText $ nid
    , h_ $
        "init add .node-highlight to "
          <> nodeSel
          <> " on htmx:beforeCleanupElement remove .node-highlight from "
          <> nodeSel
          <> " "
          <> anchorBehavior shapeSel
    ]
    $ do
      button_
        [ class_ "pill-button"
        , hxGet_ $ editLink nid pid
        , hxPushUrl_ False
        , hxSwap_ "innerHTML"
        , hxTarget_ "#node-detail"
        , hxTrigger_ "click"
        , h_ "on htmx:afterOnLoad toggle .removed on <button/>"
        ]
        $ i_ [class_ "material-icons"] "mode_edit"
      button_
        [ class_ "pill-button removed"
        , hxGet_ $ nodeDetailLink nid pid
        , hxPushUrl_ False
        , hxSwap_ "innerHTML"
        , hxTarget_ "#node-detail"
        , hxTrigger_ "click"
        , h_ $
            "on htmx:afterOnLoad"
              <> " toggle .removed on <button/>"
              <> " then trigger nodePanel:onEditClosed(nodeId:"
              <> intToText nid
              <> ")"
        ]
        $ i_ [class_ "material-icons"] "check"
      button_
        [ class_ "pill-button"
        , hxGet_ emptyLink
        , hxPushUrl'_ $ projectLink pid
        , hxSwap_ "innerHTML"
        , hxTarget_ "#node-panel"
        , hxTrigger_ "click"
        ]
        $ i_ [class_ "material-icons"] "close"
  div_
    [ id_ "node-detail"
    , hxGet_ $ nodeDetailLink nid pid
    , hxPushUrl_ False
    , hxSwap_ "innerHTML"
    , hxTarget_ "#node-detail"
    , hxTrigger_ "load"
    ]
    empty
  where
    empty = mempty :: Html ()

    nodeSel = "<[data-node-id='" <> intToText nid <> "']/>"

    -- docs/development/ui/components.md, "The node panel is anchored, not docked"
    shapeSel =
      "<#tree-container [data-node-id='" <> intToText nid <> "']/>"

-- docs/development/ui/components.md, "The node panel is anchored, not docked"
anchorBehavior :: Text -> Text
anchorBehavior shapeSel =
  T.unwords
    [ "on load or htmx:afterSwap from #node-panel"
    , "or graph:viewport from #tree-container"
    , "or resize from window"
    , "set the *maxHeight of #node-panel to ''"
    , "then measure #view"
    , "then set fT to it.top then set fB to it.bottom"
    , "then set fL to it.left then set fR to it.right"
    , "then measure the first " <> shapeSel
    , "then set nT to it.top then set nB to it.bottom"
    , "then set nL to it.left then set nW to it.width"
    , "then measure #node-panel"
    , "then set pW to it.width then set pH to it.height"
    , "then set roomBelow to ((fB - 12) - (nB + 14))"
    , "then set roomAbove to ((nT - 14) - (fT + 12))"
    , "then set below to true"
    , "then if roomBelow < pH and roomAbove > roomBelow set below to false end"
    , "then if below set room to roomBelow else set room to roomAbove end"
    , "then if room < 120 set room to 120 end"
    , "then set the *maxHeight of #node-panel to room + 'px'"
    , "then if pH > room set pH to room end"
    , "then if below set y to (nB + 14) else set y to ((nT - 14) - pH) end"
    , "then set x to ((nL + (nW / 2)) - (pW / 2))"
    , "then if x < (fL + 12) set x to (fL + 12) end"
    , "then if x > ((fR - 12) - pW) set x to ((fR - 12) - pW) end"
    , "then set the *left of #node-panel to (x - fL) + 'px'"
    , "then set the *top of #node-panel to (y - fT) + 'px'"
    ]

handler :: Int64 -> Int64 -> AppM (Html ())
handler pid nid = pure . templateNodePanel nid $ pid
