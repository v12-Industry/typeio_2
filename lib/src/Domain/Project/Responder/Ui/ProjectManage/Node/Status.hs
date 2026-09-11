{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Status where

import Common.Validation
import Domain.Project.Responder.Ui.ProjectManage.Node.Query
import Domain.Project.Responder.Ui.ProjectManage.Node.Validation
import Lucid

import qualified Domain.Project.Model as M

import Control.Monad.Reader (ReaderT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either
  ( EitherT
  , firstEitherT
  , hoistEither
  , hoistMaybe
  , runEitherT
  )
import Data.Int (Int64)
import Data.Maybe (listToMaybe)
import Data.Text (Text, unpack)
import Data.Text.Encoding (decodeUtf8)
import Database.Esqueleto.Experimental
import Network.HTTP.Types (status200, status404, status422)
import Network.Wai (Application, responseLBS)
import Network.Wai.Parse (Param, lbsBackEnd, parseRequestBody)

data PostNodeStatusErr
  = InvalidParams [ValidationErr]
  | MissingNode
  | MissingStatus

data PostNodeStatusForm = PostNodeStatusForm
  { formNodeStatus :: Maybe Text
  , formNodeId :: Maybe Text
  , formProjectId :: Maybe Text
  }

data PostNodeStatusPayload = PostNodeDescriptionPayload
  { payloadStatus :: Text
  , payloadNodeId :: Int64
  , payloadProjectId :: Int64
  }

handlePutNodeStatus :: ConnectionPool -> Application
handlePutNodeStatus pl req rspnd = do
  form <- reqForm . fst <$> parseRequestBody lbsBackEnd req
  rslt <- flip runSqlPool pl . runEitherT $ do
    pyld <-
      firstEitherT InvalidParams
        . validatePayload
        $ form
    nd <-
      lift (queryNode . payloadNodeId $ pyld)
        >>= hoistMaybe MissingNode
        >>= ( firstEitherT InvalidParams
                . validateNodeProjectId (payloadProjectId pyld)
            )
    st <-
      lift (queryStatus . payloadStatus $ pyld)
        >>= hoistMaybe MissingStatus
    lift . replace (entityKey nd) $
      (entityVal nd) {M.nodeNodeStatusId = entityKey st}
  case rslt of
    Left (InvalidParams e) ->
      rspnd
        . responseLBS
          status422
          [("Content-Type", "text/html")]
        . renderBS
        . templatePostFail
        $ e
    Left MissingNode ->
      rspnd
        . responseLBS
          status404
          [("Content-Type", "text/html")]
        . renderBS
        $ templateNodeNotFound
    Left MissingStatus ->
      rspnd
        . responseLBS
          status422
          [("Content-Type", "text/html")]
        . renderBS
        $ templatePostFail ["Node status is required"]
    Right _ ->
      rspnd
        . responseLBS
          status200
          [("Content-Type", "text/html")]
        . renderBS
        $ templatePostSuccess

queryStatus ::
  Text ->
  ReaderT SqlBackend IO (Maybe (Entity M.NodeStatus))
queryStatus st = do
  ns <- select $ do
    s <- from $ table @M.NodeStatus
    where_ $ s.nodeStatusId ==. (val . unpack $ st)
    limit 1
    pure s
  return . listToMaybe $ ns

reqForm :: [Param] -> PostNodeStatusForm
reqForm ps =
  PostNodeStatusForm
    { formNodeStatus = decodeUtf8 <$> lookup "status" ps
    , formNodeId = decodeUtf8 <$> lookup "nodeId" ps
    , formProjectId = decodeUtf8 <$> lookup "projectId" ps
    }

templatePostSuccess :: Html ()
templatePostSuccess = do
  i_ [class_ "material-icons"] "done"

templateNodeNotFound :: Html ()
templateNodeNotFound = do
  p_ [] "Node not found"

templatePostFail :: [ValidationErr] -> Html ()
templatePostFail es = do
  i_ [class_ "material-icons"] "error"
  ul_ [] $ mapM_ (li_ [] . toHtml) es

validatePayload ::
  Monad m =>
  PostNodeStatusForm ->
  EitherT [ValidationErr] m PostNodeStatusPayload
validatePayload form =
  hoistEither . runValidation id $ do
    st <-
      formNodeStatus form
        .$ id
        >>= isThere "Node status is required"
        >>= isNotEmpty "Node status cannot be empty"
    nid <-
      formNodeId form
        .$ unpack
        >>= isThere "Node id is required"
        >>= isNotEmpty "Node id must have value"
        >>= valRead "Node id must be valid integer"
    pid <-
      formProjectId form
        .$ unpack
        >>= isThere "Project id is required"
        >>= isNotEmpty "Project id must have value"
        >>= valRead "Project id must be valid integer"
    return $
      PostNodeDescriptionPayload
        <$> st
        <*> nid
        <*> pid
