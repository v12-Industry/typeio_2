{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.View where

import Common.Validation
  ( ValidationErr
  , isNotEmpty
  , isThere
  , orDefault
  , runValidation
  , valRead
  , (.$)
  )
import Common.Web.Attributes
import Common.Web.Query (lookupVal)
import Common.Web.Template.MainHeader (templateNavHeader)
import Config.Visualization (Visualization, defaultVisualization)
import Data.Int (Int64)
import Data.Text (Text, unpack)
import Domain.Project.Responder.Ui.ProjectManage.Link
import Lucid
import Network.HTTP.Types (QueryText, status200, status403)
import Network.HTTP.Types.URI (queryToQueryText)
import Network.Wai (Application, queryString, responseLBS)

data ManageProjectForm = ManageProjectForm
  { formNodeId :: Maybe Text
  , formProjectId :: Maybe Text
  , formVisualizationMode :: Maybe Text
  }

data ManageProjectPayload = ManageProjectPayload
  { payloadNodeId :: Maybe Int64
  , payloadProjectId :: Int64
  , payloadVisualization :: Visualization
  {- ^ Which drawing to ask the graph endpoint for. Resolved here, from
  this page's own @visualizationMode@, so that a link naming a drawing
  actually reaches the fragment that renders it (#223).
  -}
  }

handleProjectManageView :: Application
handleProjectManageView req respond = do
  case pidE of
    Left _ -> do
      respond $
        responseLBS
          status403
          [("Content-Type", "text/html")]
          "Bad project id"
    Right py -> do
      respond $
        responseLBS
          status200
          [("Content-Type", "text/html")]
          (renderBS $ templateProject py)
  where
    pidE =
      validateForm
        . queryTextToForm
        . queryToQueryText
        . queryString
        $ req

queryTextToForm :: QueryText -> ManageProjectForm
queryTextToForm qt =
  ManageProjectForm
    { formNodeId = lookupVal "nodeId" qt
    , formProjectId = lookupVal "projectId" qt
    , formVisualizationMode = lookupVal "visualizationMode" qt
    }

templateProject :: ManageProjectPayload -> Html ()
templateProject py = do
  templateNavHeader "Project"
  link_
    [ rel_ "stylesheet"
    , href_ "/static/styles/views/manage-project.css"
    ]
  div_ [id_ "view"] $ do
    div_
      [ id_ "tree-container"
      , -- The graph's viewport. Focusable because graph-viewport.js
        -- binds the arrow/+/-/0 keys here, which is the only way around
        -- the graph without a pointer now that the zoom buttons are
        -- gone.
        tabindex_ "0"
      , hxGet_ (graphLink pid viz)
      , hxPushUrl_ False
      , hxSwap_ "innerHTML"
      , hxTrigger_ "load"
      ]
      empty
    div_
      [ id_ "node-panel"
      ]
      empty
    case nidM of
      Nothing -> empty
      Just nid -> do
        div_
          [ class_ "hidden"
          , hxGet_ (nodePanelLink nid pid)
          , hxPushUrl_ False
          , hxTarget_ "#node-panel"
          , hxTrigger_ "load"
          , hxSync_ "#tree-container:queue last"
          ]
          empty
  where
    empty = mempty :: Html ()
    nidM = payloadNodeId py
    pid = payloadProjectId py
    viz = payloadVisualization py

validateForm :: ManageProjectForm -> Either [ValidationErr] ManageProjectPayload
validateForm fm = runValidation id $ do
  pid <-
    formProjectId fm
      .$ unpack
      >>= isThere "Project id is required"
      >>= isNotEmpty "Project id must have value"
      >>= valRead "Project id must be valid integer"
  nid <-
    formNodeId fm
      .$ unpack
      >>= valRead "Node id must be valid integer"
  {- Optional with a default rather than optional-and-nullable like
  `nid` above: an absent `visualizationMode` still has to produce a
  drawing. `orDefault` supplies it without swallowing the error from a
  value that was present and unrecognised. -}
  viz <-
    formVisualizationMode fm
      .$ unpack
      >>= valRead "Invalid visualizationMode value"
      >>= orDefault defaultVisualization
  return $ ManageProjectPayload nid <$> pid <*> viz
