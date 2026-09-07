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
    , h_ $
        "init add .node-highlight to "
          <> nodeSel
          <> " on htmx:beforeCleanupElement remove .node-highlight from "
          <> nodeSel
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
