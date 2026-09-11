{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Description where

import Common.Validation
import Domain.Project.Responder.Ui.ProjectManage.Node.Query
import Domain.Project.Responder.Ui.ProjectManage.Node.Validation
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
import Network.HTTP.Types (status200, status404, status422)
import Network.Wai (Application, responseLBS)
import Network.Wai.Parse (Param, lbsBackEnd, parseRequestBody)

data PutNodeDescriptionErr
  = InvalidParams [ValidationErr]
  | MissingNode

data PutNodeDescriptionForm = PutNodeDescriptionForm
  { formNodeDescription :: Maybe Text
  , formNodeId :: Maybe Text
  , formProjectId :: Maybe Text
  }

data PutNodeDescriptionPayload = PutNodeDescriptionPayload
  { payloadDescription :: Text
  , payloadNodeId :: Int64
  , payloadProjectId :: Int64
  }

handlePutDescription :: ConnectionPool -> Application
handlePutDescription pl req rspnd = do
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
      (entityVal nd) {M.nodeDescription = unpack . payloadDescription $ pyld}
  case rslt of
    Left (InvalidParams e) ->
      rspnd
        . responseLBS
          status422
          [("Content-Type", "text/html")]
        . renderBS
        . templatePutFail
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
        $ templatePutSuccess

reqForm :: [Param] -> PutNodeDescriptionForm
reqForm ps =
  PutNodeDescriptionForm
    { formNodeDescription = decodeUtf8 <$> lookup "description" ps
    , formNodeId = decodeUtf8 <$> lookup "nodeId" ps
    , formProjectId = decodeUtf8 <$> lookup "projectId" ps
    }

templatePutSuccess :: Html ()
templatePutSuccess = do
  i_ [class_ "material-icons"] "done"

templateNodeNotFound :: Html ()
templateNodeNotFound = do
  p_ [] "Node not found"

templatePutFail :: [ValidationErr] -> Html ()
templatePutFail es = do
  i_ [class_ "material-icons"] "error"
  ul_ [] $ mapM_ (li_ [] . toHtml) es

validatePayload ::
  Monad m =>
  PutNodeDescriptionForm ->
  EitherT [ValidationErr] m PutNodeDescriptionPayload
validatePayload form =
  hoistEither . runValidation id $ do
    dsc <-
      formNodeDescription form
        .$ id
        >>= isThere "Node description is required"
        >>= isNotEmpty "Node description cannot be empty"
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
      PutNodeDescriptionPayload
        <$> dsc
        <*> nid
        <*> pid
