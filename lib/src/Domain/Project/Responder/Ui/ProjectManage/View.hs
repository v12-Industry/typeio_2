{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.View where

import App.Env (AppM)
import App.Link
import Common.Web.Attributes
import Common.Web.Template.MainHeader (templateNavHeaderWith)
import Config.Visualization (Visualization (..), defaultVisualization)
import Data.Int (Int64)
import Data.Maybe (fromMaybe)
import Data.Text (Text, pack)
import qualified Data.Text as T
import Domain.Project.Responder.Ui.ProjectManage.SaveState (templateSaveState)
import Lucid

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
  templateToolbar pid
  div_ [id_ "view"] $ do
    div_
      ( [ id_ "tree-container"
        , tabindex_ "0"
        , hxGet_ . graphLink pid $ viz
        , hxPushUrl_ False
        , hxSwap_ "innerHTML"
        , hxTrigger_ "load, nodeCreated from:body"
        , dataViewBase_ . payloadViewBase $ py
        , h_ viewUrlBehavior
        ]
          <> viewAttrs (payloadView py)
      )
      empty
    templateAddWorkToggle pid
    div_
      [ id_ "add-work-panel"
      ]
      empty
    div_
      [ id_ "node-panel"
      ]
      empty
    templateStatsPanel
    case nidM of
      Nothing -> empty
      Just nid -> do
        div_
          [ class_ "hidden"
          , hxGet_ . nodePanelLink nid $ pid
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

templateToolbar :: Int64 -> Html ()
templateToolbar pid =
  nav_ [id_ "manage-toolbar"] $ do
    button_
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
    button_
      [ class_ "stats-toggle"
      , type_ "button"
      , ariaLabel_ "Project stats"
      , hxGet_ . projectStatsLink $ pid
      , hxPushUrl_ False
      , hxSwap_ "innerHTML"
      , hxTarget_ "#stats-body"
      , hxTrigger_ "click"
      , h_ "on click toggle .open on #stats-panel"
      ]
      "Stats"

templateAddWorkToggle :: Int64 -> Html ()
templateAddWorkToggle pid =
  button_
    [ id_ "add-work-toggle"
    , type_ "button"
    , ariaLabel_ "Add work"
    , hxGet_ . addWorkLink $ pid
    , hxPushUrl_ False
    , hxSwap_ "innerHTML"
    , hxTarget_ "#add-work-panel"
    , hxTrigger_ "click"
    ]
    "+ Add work"

templateStatsPanel :: Html ()
templateStatsPanel =
  aside_ [id_ "stats-panel"] $ do
    div_ [class_ "stats-header"] $ do
      span_ [class_ "stats-title"] "Project stats"
      button_
        [ class_ "stats-close"
        , type_ "button"
        , ariaLabel_ "Close project stats"
        , h_ "on click remove .open from #stats-panel"
        ]
        "✕"
    div_ [id_ "stats-body"] (mempty :: Html ())

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

handler ::
  Int64 ->
  Maybe Int64 ->
  Maybe Visualization ->
  Maybe Double ->
  Maybe Double ->
  Maybe Double ->
  AppM (Html ())
handler pid nid mviz vx vy vk =
  pure $
    templateProject
      ManageProjectPayload
        { payloadNodeId = nid
        , payloadProjectId = pid
        , payloadVisualization = viz
        , payloadView = ViewTransform <$> vx <*> vy <*> vk
        , payloadViewBase = viewBaseFromParams pid nid viz
        }
  where
    viz = fromMaybe defaultVisualization mviz

{- Rebuilt from the parameters the route actually parsed rather than from
   the raw query string, so the base the viewport appends to is canonical
   whatever the client sent. -}
viewBaseFromParams :: Int64 -> Maybe Int64 -> Visualization -> Text
viewBaseFromParams pid nid viz = projectViewLink pid nid (Just viz)
