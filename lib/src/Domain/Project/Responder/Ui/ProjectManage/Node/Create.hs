{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Create where

import App.Env (AppM, runDb)
import App.Handler (htmlError)
import App.Link
  ( addWorkSubmitLink
  , emptyLink
  )
import Common.Validation
  ( ValidationErr
  , isNotEmpty
  , isThere
  , runValidation
  , valRead
  , (.$)
  )
import Common.Web.Attributes
import Control.Monad (forM_, unless)
import Control.Monad.Error.Class (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either (hoistEither, hoistMaybe, runEitherT)
import Data.Bifunctor (first)
import Data.Int (Int64)
import Data.Text (Text, strip, unpack)
import Data.Text.Util (intToText)
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist (Entity (..))
import Database.Persist.Sql (SqlBackend, fromSqlKey, insert)
import qualified Domain.Project.Model as M
import Domain.Project.Responder.Ui.ProjectManage.Node (templateNodePanel)
import Domain.Project.Responder.Ui.ProjectManage.Node.Query
  ( queryNodeStatus
  , queryNodeType
  , queryProject
  )
import Lucid
import Servant (Header, Headers, addHeader, err422, err500)
import Web.FormUrlEncoded (Form, lookupMaybe)

data CreateWorkError
  = FormInvalid [ValidationErr]
  | TitleInvalid Int64 [ValidationErr]
  | ProjectMissing Int64
  | ReferenceMissing

data AddWorkForm = AddWorkForm
  { formProjectId :: Maybe Text
  , formTitle :: Maybe Text
  }

formToAddWorkForm :: Form -> AddWorkForm
formToAddWorkForm f =
  AddWorkForm
    { formProjectId = look "projectId"
    , formTitle = look "title"
    }
  where
    look k = case lookupMaybe k f of
      Right (Just v) -> Just v
      _ -> Nothing

createWork ::
  UTCTime ->
  AddWorkForm ->
  ReaderT SqlBackend IO (Either CreateWorkError (Entity M.Node))
createWork now form = runEitherT $ do
  pid <-
    hoistEither
      . first FormInvalid
      . validateProjectId
      $ formProjectId form
  ttl <-
    hoistEither
      . first (TitleInvalid pid)
      . validateTitle
      $ formTitle form
  prj <- lift (queryProject pid) >>= hoistMaybe (ProjectMissing pid)
  sts <- lift (queryNodeStatus "active") >>= hoistMaybe ReferenceMissing
  typ <- lift (queryNodeType "work") >>= hoistMaybe ReferenceMissing
  let nde = newWorkNode now ttl prj sts typ
  ky <- lift . insert $ nde
  pure . Entity ky $ nde

newWorkNode ::
  UTCTime ->
  Text ->
  Entity M.Project ->
  Entity M.NodeStatus ->
  Entity M.NodeType ->
  M.Node
newWorkNode now ttl prj sts typ =
  M.Node
    { M.nodeCreated = now
    , M.nodeDeleted = Nothing
    , M.nodeDescription = ""
    , M.nodeNodeStatusId = entityKey sts
    , M.nodeNodeTypeId = entityKey typ
    , M.nodeProjectId = entityKey prj
    , M.nodeTitle = unpack ttl
    , M.nodeUpdated = now
    }

templateAddWork :: Int64 -> [ValidationErr] -> Html ()
templateAddWork pid es =
  form_
    [ id_ "add-work-form"
    , hxPost_ addWorkSubmitLink
    , hxPushUrl_ False
    , hxSwap_ "innerHTML"
    , hxTarget_ "#add-work-panel"
    , hxTrigger_ "submit"
    , dataSaves_
    ]
    $ do
      div_ [class_ "panel-heading"] $ do
        span_ [class_ "panel-title"] "New work"
        button_
          [ class_ "panel-close"
          , type_ "button"
          , ariaLabel_ "Close add work"
          , hxGet_ emptyLink
          , hxPushUrl_ False
          , hxSwap_ "innerHTML"
          , hxTarget_ "#add-work-panel"
          , hxTrigger_ "click"
          ]
          "✕"
      label_ [for_ "work-title"] "Title"
      input_
        [ type_ "text"
        , id_ "work-title"
        , name_ "title"
        , autofocus_
        , autocomplete_ "off"
        , placeholder_ "What needs doing?"
        ]
      input_
        [ type_ "hidden"
        , name_ "projectId"
        , value_ . intToText $ pid
        ]
      unless (null es) $ templateErrors es
      div_ [class_ "panel-footer"] $
        button_ [class_ "add-work-submit", type_ "submit"] "Create"

templateCreated :: Int64 -> Int64 -> Html ()
templateCreated nid pid =
  div_ [id_ "node-panel", hxSwapOob_ "innerHTML"] $
    templateNodePanel nid pid

templateErrors :: [ValidationErr] -> Html ()
templateErrors es =
  ul_ [class_ "error-messages"] $
    forM_ es (li_ [class_ "error-message"] . toHtml)

validateProjectId :: Maybe Text -> Either [ValidationErr] Int64
validateProjectId raw = runValidation id $ do
  pid <-
    raw
      .$ unpack
      >>= isThere "Project id is required"
      >>= isNotEmpty "Project id must have value"
      >>= valRead "Project id must be valid integer"
  return pid

validateTitle :: Maybe Text -> Either [ValidationErr] Text
validateTitle raw = runValidation id $ do
  ttl <-
    raw
      .$ strip
      >>= isThere "Title is required"
      >>= isNotEmpty "Title cannot be empty"
  return ttl

handler :: Int64 -> AppM (Html ())
handler pid = pure (templateAddWork pid [])

submitHandler :: Form -> AppM (Headers '[Header "HX-Trigger" Text] (Html ()))
submitHandler form = do
  now <- liftIO getCurrentTime
  rslt <- runDb . createWork now . formToAddWorkForm $ form
  case rslt of
    Left (FormInvalid es) -> throwError . htmlError err422 . templateErrors $ es
    Left (TitleInvalid pid es) ->
      throwError . htmlError err422 . templateAddWork pid $ es
    Left (ProjectMissing pid) ->
      throwError . htmlError err422 . templateAddWork pid $ ["Project not found"]
    Left ReferenceMissing ->
      throwError
        . htmlError err500
        . templateErrors
        $ ["The database is missing its reference data"]
    Right (Entity ky nde) ->
      pure
        . addHeader "nodeCreated"
        . templateCreated (fromSqlKey ky)
        . fromSqlKey
        . M.nodeProjectId
        $ nde
