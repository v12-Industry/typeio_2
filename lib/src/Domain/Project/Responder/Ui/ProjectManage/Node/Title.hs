{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Title where

import Common.Validation
import Domain.Project.Responder.Ui.ProjectManage.Node.Query
import Domain.Project.Responder.Ui.ProjectManage.Node.Validation
import Domain.Project.Responder.Ui.ProjectManage.SaveState
  ( templateSaveStateIdle
  , templateSaveStateSaved
  )
import Lucid

import qualified Domain.Project.Model as M

import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either
  ( EitherT
  , firstEitherT
  , hoistEither
  , hoistMaybe
  , runEitherT
  )
import Data.Int (Int64)
import Data.Text (Text, unpack)
import Data.Text.Encoding (decodeUtf8)
import Database.Esqueleto.Experimental
import Network.HTTP.Types (status200, status404)
import Network.Wai (Application, responseLBS)
import Network.Wai.Parse (Param, lbsBackEnd, parseRequestBody)

data PutTitleErr
  = InvalidParams [ValidationErr]
  | MissingNode

data PutNodeTitleForm = PutNodeTitleForm
  { formNodeTitle :: Maybe Text
  , formNodeId :: Maybe Text
  , formProjectId :: Maybe Text
  }

data PutNodeTitlePayload = PutNodeTitlePayload
  { payloadNodeId :: Int64
  , payloadProjectId :: Int64
  , payloadTitle :: Text
  }

handlePutTitle :: ConnectionPool -> Application
handlePutTitle pl req rspnd = do
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
    lift . replace (entityKey nd) $
      (entityVal nd) {M.nodeTitle = unpack . payloadTitle $ pyld}
  case rslt of
    Left (InvalidParams e) ->
      rspnd
        . responseLBS
          status200
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
    Right _ ->
      rspnd
        . responseLBS
          status200
          [("Content-Type", "text/html")]
        . renderBS
        $ templatePostSuccess

reqForm :: [Param] -> PutNodeTitleForm
reqForm ps =
  PutNodeTitleForm
    { formNodeId = decodeUtf8 <$> lookup "nodeId" ps
    , formProjectId = decodeUtf8 <$> lookup "projectId" ps
    , formNodeTitle = decodeUtf8 <$> lookup "title" ps
    }

templatePostSuccess :: Html ()
templatePostSuccess = do
  span_ [class_ "loading hidden"] empty
  i_ [class_ "material-icons"] "done"
  templateSaveStateSaved
  where
    empty = mempty :: Html ()

templateNodeNotFound :: Html ()
templateNodeNotFound = do
  p_ [] "Node not found"

templatePostFail :: [ValidationErr] -> Html ()
templatePostFail es = do
  i_ [class_ "material-icons"] "error"
  ul_ [] $ mapM_ (li_ [] . toHtml) es
  templateSaveStateIdle

validatePayload ::
  Monad m =>
  PutNodeTitleForm ->
  EitherT [ValidationErr] m PutNodeTitlePayload
validatePayload form =
  hoistEither . runValidation id $ do
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
    ttl <-
      formNodeTitle form
        .$ id
        >>= isThere "Node title is required"
        >>= isNotEmpty "Node title cannot be empty"
    return $
      PutNodeTitlePayload
        <$> nid
        <*> pid
        <*> ttl
