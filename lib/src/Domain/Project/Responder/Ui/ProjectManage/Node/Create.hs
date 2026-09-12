{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Create where

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
import Control.Monad (forM_, unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either (hoistMaybe, runEitherT)
import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.Text (Text, strip, unpack)
import Data.Text.Encoding (decodeUtf8)
import Data.Text.Util (intToText)
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist (Entity (..))
import Database.Persist.Sql (ConnectionPool, fromSqlKey, insert, runSqlPool)
import qualified Domain.Project.Model as M
import Domain.Project.Responder.Ui.ProjectManage.Link
  ( addWorkSubmitLink
  , emptyLink
  )
import Domain.Project.Responder.Ui.ProjectManage.Node (templateNodePanel)
import Domain.Project.Responder.Ui.ProjectManage.Node.Query
  ( queryNodeStatus
  , queryNodeType
  , queryProject
  )
import Lucid
import Network.HTTP.Types (HeaderName, status200, status422, status500)
import Network.HTTP.Types.URI (QueryText, queryToQueryText)
import Network.Wai (Application, queryString, responseLBS)
import Network.Wai.Parse (lbsBackEnd, parseRequestBody)

data CreateWorkError
  = ProjectMissing
  | ReferenceMissing

handleGetAddWork :: Application
handleGetAddWork req respond =
  case validateProjectId (lookupVal "projectId" qt) of
    Left es ->
      respond
        . responseLBS status422 [htmlContent]
        . renderBS
        . templateErrors
        $ es
    Right pid ->
      respond
        . responseLBS status200 [htmlContent]
        . renderBS
        $ templateAddWork pid []
  where
    qt = queryToQueryText . queryString $ req

handlePostWork :: ConnectionPool -> Application
handlePostWork pl req respond = do
  form <- fst <$> parseRequestBody lbsBackEnd req
  now <- getCurrentTime
  case validateProjectId (param "projectId" form) of
    Left es -> respond . invalid . templateErrors $ es
    Right pid -> case validateTitle (param "title" form) of
      Left es -> respond . invalid . templateAddWork pid $ es
      Right ttl -> do
        rslt <- flip runSqlPool pl . runEitherT $ do
          prj <- lift (queryProject pid) >>= hoistMaybe ProjectMissing
          sts <- lift (queryNodeStatus "active") >>= hoistMaybe ReferenceMissing
          typ <- lift (queryNodeType "work") >>= hoistMaybe ReferenceMissing
          lift . insert $ newWorkNode now ttl prj sts typ
        case rslt of
          Left ProjectMissing ->
            respond
              . invalid
              . templateAddWork pid
              $ ["Project not found"]
          Left ReferenceMissing ->
            respond
              . responseLBS status500 [htmlContent]
              . renderBS
              . templateErrors
              $ ["The database is missing its reference data"]
          Right key ->
            respond
              . responseLBS status200 [htmlContent, createdTrigger]
              . renderBS
              . templateCreated (fromSqlKey key)
              $ pid
  where
    param k = fmap decodeUtf8 . lookup k
    invalid = responseLBS status422 [htmlContent] . renderBS

htmlContent :: (HeaderName, ByteString)
htmlContent = ("Content-Type", "text/html")

createdTrigger :: (HeaderName, ByteString)
createdTrigger = ("HX-Trigger", "nodeCreated")

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
        , value_ (intToText pid)
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
