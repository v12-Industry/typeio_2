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
import qualified Data.Text as T
import Data.Text.Encoding (decodeUtf8)
import Domain.Project.Responder.Ui.ProjectManage.Link
import Domain.Project.Responder.Ui.ProjectManage.SaveState (templateSaveState)
import Lucid
import Lucid.Base (Attributes)
import Network.HTTP.Types (QueryText, status200, status302, status403)
import Network.HTTP.Types.URI (queryTextToQuery, queryToQueryText, renderQuery)
import Network.Wai
  ( Application
  , Request (queryString, rawPathInfo)
  , responseLBS
  )
import Text.Read (readMaybe)

data ManageProjectForm = ManageProjectForm
  { formNodeId :: Maybe Text
  , formProjectId :: Maybe Text
  }

data ManageProjectPayload = ManageProjectPayload
  { payloadNodeId :: Maybe Int64
  , payloadProjectId :: Int64
  , payloadVisualization :: Visualization
  , payloadView :: Maybe ViewTransform
  , payloadViewBase :: Text
  }

data ViewTransform = ViewTransform
  { viewX :: Double
  , viewY :: Double
  , viewScale :: Double
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
      case validateForm viz (viewTransform qt) (viewBase req qt) (queryTextToForm qt) of
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

viewTransform :: QueryText -> Maybe ViewTransform
viewTransform qt =
  ViewTransform
    <$> dbl "viewX"
    <*> dbl "viewY"
    <*> dbl "viewScale"
  where
    dbl k = lookupVal k qt >>= readMaybe . unpack

-- docs/development/frontend/index.md's viewport section
viewBase :: Request -> QueryText -> Text
viewBase req qt =
  decodeUtf8 $
    rawPathInfo req
      <> renderQuery True (queryTextToQuery (filter (not . isViewParam) qt))
  where
    isViewParam (k, _) = k `elem` ["viewX", "viewY", "viewScale"]

viewAttrs :: Maybe ViewTransform -> [Attributes]
viewAttrs Nothing = []
viewAttrs (Just vt) =
  [ dataViewX_ (dblText (viewX vt))
  , dataViewY_ (dblText (viewY vt))
  , dataViewScale_ (dblText (viewScale vt))
  ]

dblText :: Double -> Text
dblText = pack . show

templateProject :: ManageProjectPayload -> Html ()
templateProject py = do
  templateNavHeaderWith "Project" templateSaveState
  link_
    [ rel_ "stylesheet"
    , href_ "/static/styles/views/manage-project.css"
    ]
  templateToolbar
  div_ [id_ "view"] $ do
    div_
      ( [ id_ "tree-container"
        , tabindex_ "0"
        , hxGet_ (graphLink pid viz)
        , hxPushUrl_ False
        , hxSwap_ "innerHTML"
        , hxTrigger_ "load"
        , dataViewBase_ (payloadViewBase py)
        , h_ viewUrlBehavior
        ]
          <> viewAttrs (payloadView py)
      )
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

templateToolbar :: Html ()
templateToolbar =
  nav_ [id_ "manage-toolbar"]
    $ button_
      [ class_ "back-link"
      , type_ "button"
      , ariaLabel_ "Back to projects"
      , hxGet_ projectIndexLink
      , hxPushUrl_ True
      , hxSwap_ "innerHTML"
      , hxTarget_ "#container"
      ]
    $ do
      span_ [class_ "back-link-arrow"] "←"
      span_ "Back to projects"

-- docs/architecture/graph-rendering.md's Viewport section
viewUrlBehavior :: Text
viewUrlBehavior =
  T.unwords
    [ "init set my.base to @data-view-base end"
    , "on graph:viewport debounced at 200ms"
    , "set my.view to event.detail"
    , "then set url to my.base"
    , "then if my.view.adjusted set url to url"
    , "+ '&viewX=' + my.view.x"
    , "+ '&viewY=' + my.view.y"
    , "+ '&viewScale=' + my.view.k end"
    , "then call window.history.replaceState(window.history.state, '', url)"
    , "end"
    , "on htmx:pushedIntoHistory from body"
    , "set my.base to window.location.pathname + window.location.search"
    , "then if my.view is not null"
    , "trigger graph:viewport(x: my.view.x, y: my.view.y,"
    , "k: my.view.k, adjusted: my.view.adjusted)"
    , "end"
    , "end"
    ]

validateForm ::
  Visualization ->
  Maybe ViewTransform ->
  Text ->
  ManageProjectForm ->
  Either [ValidationErr] ManageProjectPayload
validateForm viz vt base fm = runValidation id $ do
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
  return $
    ManageProjectPayload nid <$> pid <*> pure viz <*> pure vt <*> pure base
