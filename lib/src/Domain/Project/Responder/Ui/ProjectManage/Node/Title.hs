{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Title where

import Common.Validation
import Lucid

import qualified Domain.Project.Model as M

import App.Env (AppM)
import App.Handler (FieldUpdateErr (..), nodeForUpdate, updateNodeField)
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

formToPutNodeTitleForm :: Form -> PutNodeTitleForm
formToPutNodeTitleForm f =
  PutNodeTitleForm
    { formNodeTitle = look "title"
    , formNodeId = look "nodeId"
    , formProjectId = look "projectId"
    }
  where
    look k = case lookupMaybe k f of
      Right (Just v) -> Just v
      _ -> Nothing

templatePostSuccess :: Html ()
templatePostSuccess = do
  span_ [class_ "loading hidden"] empty
  i_ [class_ "material-icons"] "done"
  where
    empty = mempty :: Html ()

templateNodeNotFound :: Html ()
templateNodeNotFound = do
  p_ [] "Node not found"

templatePostFail :: [ValidationErr] -> Html ()
templatePostFail es = do
  i_ [class_ "material-icons"] "error"
  ul_ [] $ mapM_ (li_ [] . toHtml) es

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

handler :: Form -> AppM (Html ())
handler form =
  updateNodeField
    templateNodeNotFound
    templatePostFail
    templatePostSuccess
    $ do
      pyld <-
        firstEitherT FieldInvalid
          . validatePayload
          . formToPutNodeTitleForm
          $ form
      nde <- nodeForUpdate (payloadProjectId pyld) (payloadNodeId pyld)
      lift . replace (entityKey nde) $
        (entityVal nde) {M.nodeTitle = unpack (payloadTitle pyld)}
