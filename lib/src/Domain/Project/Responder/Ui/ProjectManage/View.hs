{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.View where

import Common.Validation
  ( ValidationErr
  , isNotEmpty
  , isThere
  , runValidation
  , valRead
  , (.$)
  )
import Common.Web.Attributes
import Common.Web.Query (lookupVal, setQueryParam)
import Common.Web.Template.MainHeader (templateNavHeaderWith)
import Config.Visualization
  ( Visualization
  , VisualizationChoice (..)
  , resolveVisualization
  )
import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.Text (Text, pack, unpack)
import Domain.Project.Responder.Ui.ProjectManage.Link
import Domain.Project.Responder.Ui.ProjectManage.SaveState (templateSaveState)
import Lucid
import Network.HTTP.Types (QueryText, status200, status302, status403)
import Network.HTTP.Types.URI (queryTextToQuery, queryToQueryText, renderQuery)
import Network.Wai
  ( Application
  , Request (queryString, rawPathInfo)
  , responseLBS
  )

data ManageProjectForm = ManageProjectForm
  { formNodeId :: Maybe Text
  , formProjectId :: Maybe Text
  }

data ManageProjectPayload = ManageProjectPayload
  { payloadNodeId :: Maybe Int64
  , payloadProjectId :: Int64
  , payloadVisualization :: Visualization
  }

handleProjectManageView :: Application
handleProjectManageView req respond =
  case resolveVisualization (lookupVal "visualizationMode" qt) of
    FellBack viz ->
      respond $
        responseLBS
          status302
          [("Location", visualizationLocation req qt viz)]
          mempty
    AsRequested viz ->
      case validateForm viz (queryTextToForm qt) of
        Left _ ->
          respond $
            responseLBS
              status403
              [("Content-Type", "text/html")]
              "Bad project id"
        Right py ->
          respond $
            responseLBS
              status200
              [("Content-Type", "text/html")]
              (renderBS $ templateProject py)
  where
    qt = queryToQueryText . queryString $ req

visualizationLocation :: Request -> QueryText -> Visualization -> ByteString
visualizationLocation req qt viz =
  rawPathInfo req
    <> renderQuery True (queryTextToQuery corrected)
  where
    corrected = setQueryParam "visualizationMode" (pack (show viz)) qt

queryTextToForm :: QueryText -> ManageProjectForm
queryTextToForm qt =
  ManageProjectForm
    { formNodeId = lookupVal "nodeId" qt
    , formProjectId = lookupVal "projectId" qt
    }

templateProject :: ManageProjectPayload -> Html ()
templateProject py = do
  templateNavHeaderWith "Project" templateSaveState
  link_
    [ rel_ "stylesheet"
    , href_ "/static/styles/views/manage-project.css"
    ]
  div_ [id_ "view"] $ do
    div_
      [ id_ "tree-container"
      , tabindex_ "0"
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

validateForm ::
  Visualization ->
  ManageProjectForm ->
  Either [ValidationErr] ManageProjectPayload
validateForm viz fm = runValidation id $ do
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
  return $ ManageProjectPayload nid <$> pid <*> pure viz
