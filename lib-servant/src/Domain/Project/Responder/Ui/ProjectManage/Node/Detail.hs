{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Detail where

import Common.Validation
  ( ValidationErr
  , isNotEmpty
  , isThere
  , runValidation
  , valRead
  , (.$)
  )
import Common.Web.Query (lookupVal)
import Control.Monad (forM_, unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either (EitherT, firstEitherT, hoistEither, hoistMaybe, runEitherT)
import Data.Int (Int64)
import Data.Text (Text, pack, unpack)
import Data.Time (UTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Database.Persist (Entity (..))
import Database.Persist.Sql (ConnectionPool, runSqlPool)
import qualified Domain.Project.Model as M
import Domain.Project.Responder.Ui.ProjectManage.Node.Query
import Domain.Project.Responder.Ui.ProjectManage.Node.Validation
import Lucid
import Network.HTTP.Types (status200)
import Network.HTTP.Types.URI (QueryText, queryToQueryText)
import Network.Wai (Request, Response, ResponseReceived, queryString, responseLBS)

data NodeDetailError
  = InvalidParams [ValidationErr]
  | NodeNotFound

data GetNodeDetailForm = GetNodeDetailForm
  { formProjectId :: Maybe Text
  , formNodeId :: Maybe Text
  }

data GetNodeDetailPayload = GetNodeDetailPayload
  { payloadProjectId :: Int64
  , payloadNodeId :: Int64
  }

formatUpdated :: UTCTime -> Text
formatUpdated = pack . formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S"

handleErr :: NodeDetailError -> Response
handleErr er = case er of
  (InvalidParams es) ->
    responseLBS
      status200
      [("Content-Type", "text/html")]
      . renderBS
      . templateInvalidParams
      $ es
  NodeNotFound -> do
    responseLBS
      status200
      [("Content-Type", "text/html")]
      . renderBS
      $ templateNodeNotFound

handleGetNodeDetail ::
  ConnectionPool ->
  Request ->
  (Response -> IO ResponseReceived) ->
  IO ResponseReceived
handleGetNodeDetail pl req respond = do
  rslt <- flip runSqlPool pl . runEitherT $ do
    pyld <-
      firstEitherT InvalidParams
        . validateForm
        $ form
    lift (queryNode . payloadNodeId $ pyld)
      >>= hoistMaybe NodeNotFound
      >>= ( firstEitherT InvalidParams
              . validateNodeProjectId (payloadProjectId pyld)
          )
  case rslt of
    Left e -> respond . handleErr $ e
    Right nde ->
      respond
        . responseLBS
          status200
          [("Content-Type", "text-html")]
        . renderBS
        . templateNodeDetail
        . entityVal
        $ nde
  where
    form =
      queryTextToForm
        . queryToQueryText
        . queryString
        $ req

queryTextToForm :: QueryText -> GetNodeDetailForm
queryTextToForm qt =
  GetNodeDetailForm
    { formProjectId = lookupVal "projectId" qt
    , formNodeId = lookupVal "nodeId" qt
    }

showNodeType :: Text -> Text
showNodeType typ = case typ of
  "project_root" -> "Root"
  "work" -> "Work"
  _ -> typ

templateNodeNotFound :: Html ()
templateNodeNotFound = do
  div_ [] "Node not found"

templateInvalidParams :: [ValidationErr] -> Html ()
templateInvalidParams es = do
  div_ [] $ do
    unless (null es) $ do
      div_ [class_ "error-messages"] $ do
        forM_ es $ p_ [class_ "error-message"] . toHtml

templateNodeDetail :: M.Node -> Html ()
templateNodeDetail nde = do
  header_ [] $
    h2_ [] (toHtml . pack . M.nodeTitle $ nde)
  section_ [] $
    p_ [] (toHtml . pack . M.nodeDescription $ nde)
  section_ [id_ "node-properties"] $ do
    article_ [] $ do
      span_ [class_ "property-label"] "Status:"
      span_ [class_ "property-value"] (toHtml . pack . M.unNodeStatusKey . M.nodeNodeStatusId $ nde)
    article_ [] $ do
      span_ [class_ "property-label"] "Type:"
      span_ [class_ "property-value"] (toHtml . pack . M.unNodeTypeKey . M.nodeNodeTypeId $ nde)
    article_ [] $ do
      span_ [class_ "property-label"] "Last Updated:"
      span_ [class_ "property-value"] (toHtml . formatUpdated . M.nodeUpdated $ nde)

validateForm ::
  Monad m =>
  GetNodeDetailForm ->
  EitherT [ValidationErr] m GetNodeDetailPayload
validateForm fm = hoistEither . runValidation id $ do
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
  return $ GetNodeDetailPayload <$> pid <*> nid
