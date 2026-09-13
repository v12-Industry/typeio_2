{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectIndex.View where

import App.Env (AppM)
import App.Link (createProjectLink, projectListLink)
import Common.Web.Attributes
import Common.Web.Template.MainHeader (templateNavHeader)
import Lucid

projectIndexVwTemplate :: Html ()
projectIndexVwTemplate = do
  templateNavHeader "Projects"
  div_ [id_ "view"] $ do
    button_
      [ class_ "action-button"
      , hxGet_ createProjectLink
      , hxPushUrl_ True
      , hxTarget_ "#container"
      , hxSwap_ "innerHTML"
      ]
      "Create Project"
    div_
      [ hxGet_ projectListLink
      , hxPushUrl_ False
      , hxTrigger_ "load"
      , hxSwap_ "innerHTML"
      ]
      mempty

handler :: AppM (Html ())
handler = pure projectIndexVwTemplate
