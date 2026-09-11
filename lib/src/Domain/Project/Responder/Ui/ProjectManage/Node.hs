{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Node where

import Common.Validation
  ( ValidationErr
  , isNotEmpty
  , isThere
  , runValidation
  , valRead
  , (.$)
  )
import Common.Web.Attributes
import Common.Web.Query (lookupVal)
import Data.Int (Int64)
import Data.Text (Text, unpack)
import qualified Data.Text as T
import Data.Text.Util (intToText)
import Domain.Project.Responder.Ui.ProjectManage.Link
import Lucid
import Network.HTTP.Types.Status (status200, status400)
import Network.HTTP.Types.URI (QueryText, queryToQueryText)
import Network.Wai (Application, queryString, responseLBS)

data GetNodePanelForm = GetNodePanelForm
  { formNodeId :: Maybe Text
  , formProjectId :: Maybe Text
  }

data GetNodePanelPayload = GetNodePanelPayload
  { payloadNodeId :: Int64
  , payloadProjectId :: Int64
  }

handleGetNodePanel :: Application
handleGetNodePanel req respond = do
  case pyld of
    Left _ ->
      respond
        . responseLBS
          status400
          []
        $ "Error"
    Right payload ->
      respond
        . responseLBS
          status200
          []
        . renderBS
        . templateNodePanel (payloadNodeId payload)
        $ payloadProjectId payload
  where
    pyld =
      validateForm
        . queryTextToForm
        . queryToQueryText
        . queryString
        $ req

queryTextToForm :: QueryText -> GetNodePanelForm
queryTextToForm qt =
  GetNodePanelForm
    { formProjectId = lookupVal "projectId" qt
    , formNodeId = lookupVal "nodeId" qt
    }

templateNodePanel :: Int64 -> Int64 -> Html ()
templateNodePanel nid pid = do
  div_
    [ class_ "panel-actions"
    , dataNodeId_ (intToText nid)
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
        , hxGet_ "/ui/central/empty"
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

    -- Scoped to the drawing. The panel's own body carries the same
    -- data-node-id, and an unscoped selector would let the panel
    -- measure itself instead of the node it is pointing at.
    shapeSel =
      "<#tree-container [data-node-id='" <> intToText nid <> "']/>"

{- | Positions the detail panel against the node it describes.

The panel is an absolutely-positioned element inside @#view@, but the
node it points at is a shape inside an SVG the user pans and zooms, so
"next to that shape" is not something CSS can state. Everything here is
measurement: the stylesheet still owns how the panel looks.

It re-places whenever the drawing moves under it, which is what the
viewport's @graph:viewport@ event is for, and whenever the panel's own
contents change height -- an edit form is taller than the detail it
replaces, and the flip below is decided from that height.

The flip is the point. The panel sits under its node, goes above when
the room underneath has run out, and takes the roomier side when neither
fits. When it is taller than that side it gives up height rather than
ground: a panel that clamped itself into view would settle on top of the
node it is pointing at, so it caps itself and scrolls instead.

Every arithmetic expression is parenthesised because hyperscript does
not rank its operators -- mixing @+@ and @/@ without brackets is a parse
error, not a precedence surprise.

Orbital draws one node once per work stream, so the selector can match
several shapes. @the first@ is required rather than stylistic: @measure@
takes an element, and handing it a collection is a runtime error. The
panel anchors to the first replica in document order.
-}
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

validateForm :: GetNodePanelForm -> Either [ValidationErr] GetNodePanelPayload
validateForm fm = runValidation id $ do
  pid <-
    formProjectId fm
      .$ unpack
      >>= isThere "Project id must be present"
      >>= isNotEmpty "Project id must have a value"
      >>= valRead "Project id must be valid integer"
  nid <-
    formNodeId fm
      .$ unpack
      >>= isThere "Node id must be present"
      >>= isNotEmpty "Node id must have a value"
      >>= valRead "Node id must be valid integer"
  return $ GetNodePanelPayload <$> nid <*> pid
