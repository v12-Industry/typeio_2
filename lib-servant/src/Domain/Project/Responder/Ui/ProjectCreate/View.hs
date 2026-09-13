{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectCreate.View where

import Common.Web.Attributes
import Common.Web.Template.MainHeader (templateNavHeader)
import Control.Monad (forM_, unless)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Lucid
import Network.HTTP.Types (status200)
import Network.Wai (Response, ResponseReceived, responseLBS)

data AddProjectForm = AddProjectForm
  { description :: Maybe Text
  , title :: Maybe Text
  }

emptyForm :: AddProjectForm
emptyForm =
  AddProjectForm
    { description = Nothing
    , title = Nothing
    }

handleProjectCreateVw :: (Response -> IO ResponseReceived) -> IO ResponseReceived
handleProjectCreateVw respond = do
  respond $
    responseLBS
      status200
      [("Content-Type", "text/html; charset=utf-8")]
      (renderBS $ projectCreateVwTemplate emptyForm mempty)

projectCreateVwTemplate :: AddProjectForm -> [Text] -> Html ()
projectCreateVwTemplate payload errs = do
  templateNavHeader "Add Project"
  link_ [rel_ "stylesheet", href_ "/static/styles/views/add-project.css"]
  div_ [id_ "view"] $ do
    form_
      [ id_ "form-create-project"
      , class_ "form-basic"
      , hxPost_ "/ui/create-project/submit"
      ]
      $ do
        span_ $ do
          label_ [for_ "title"] "Title:"
          input_ [type_ "text", id_ "title", name_ "title", value_ ttle]
        span_ $ do
          label_ [for_ "description"] "Description:"
          textarea_ [id_ "description", name_ "description"] (toHtml dscr)
        span_ $ do
          button_
            [ class_ "action-button"
            , type_ "submit"
            ]
            "Submit"
        unless (null errs) $ do
          div_ [class_ "error-messages"] $ do
            forM_ errs $ p_ [class_ "error-message"] . toHtml
  where
    dscr = fromMaybe mempty $ description payload
    ttle = fromMaybe mempty $ title payload
