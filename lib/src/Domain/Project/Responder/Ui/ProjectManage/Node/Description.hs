{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Description where

import Common.Validation
import Lucid

import qualified Domain.Project.Model as M

import App.Env (AppM)
import App.Handler (FieldUpdateErr (..), lookupNode, updateNodeField)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either
  ( EitherT
  , firstEitherT
  , hoistEither
  )
import Data.Int (Int64)
import Data.Text (Text, unpack)
import Database.Esqueleto.Experimental
import Web.FormUrlEncoded (Form, lookupMaybe)

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

formToPutNodeDescriptionForm :: Form -> PutNodeDescriptionForm
formToPutNodeDescriptionForm f =
  PutNodeDescriptionForm
    { formNodeDescription = look "description"
    , formNodeId = look "nodeId"
    , formProjectId = look "projectId"
    }
  where
    look k = case lookupMaybe k f of
      Right (Just v) -> Just v
      _ -> Nothing

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

handler :: Form -> AppM (Html ())
handler form =
  updateNodeField
    templateNodeNotFound
    templatePutFail
    templatePutSuccess
    $ do
      pyld <-
        firstEitherT FieldInvalid
          . validatePayload
          . formToPutNodeDescriptionForm
          $ form
      nde <- lookupNode (payloadProjectId pyld) (payloadNodeId pyld)
      lift . replace (entityKey nde) $
        (entityVal nde) {M.nodeDescription = unpack (payloadDescription pyld)}
