{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Domain.Project.Responder.Api.Node.Post where

import App.Api (CreatedNode (..))
import App.Env (AppM, runDb)
import App.Link (nodeResourceLink)
import Common.Validation
  ( ValidationErr
  , isNotEmpty
  , isThere
  , runValidation
  , valRead
  , (.$)
  )
import Control.Monad.Error.Class (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either (hoistEither, hoistMaybe, runEitherT)
import Data.Aeson
  ( ToJSON (..)
  , encode
  , object
  , (.=)
  )
import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.Maybe (listToMaybe)
import Data.Text (Text, unpack)
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Time (UTCTime, getCurrentTime)
import Database.Esqueleto.Experimental
  ( Entity
  , from
  , insert
  , limit
  , select
  , table
  , toSqlKey
  , val
  , where_
  , (==.)
  )
import Database.Persist (Entity (..))
import Database.Persist.Sql (SqlBackend, fromSqlKey)
import qualified Domain.Project.Model as M
import Servant (Header, Headers, addHeader, err404, err422, err500, errBody)
import Web.FormUrlEncoded (Form, lookupMaybe)

data InsertNodeResult
  = FailValidation [ValidationErr]
  | MissingStatus
  | MissingType
  | ProjectNotFound

data PostNodeForm = PostNodeForm
  { formDescription :: Maybe ByteString
  , formProjectId :: Maybe ByteString
  , formTitle :: Maybe ByteString
  }

data PostNodePayload = PostNodePayload
  { description :: Text
  , projectId :: Int64
  , title :: Text
  }

instance ToJSON PostNodePayload where
  toJSON (PostNodePayload desc pid ttl) =
    object
      [ "description" .= desc
      , "projectId" .= pid
      , "title" .= ttl
      ]

formToPostNodeForm :: Form -> PostNodeForm
formToPostNodeForm f =
  PostNodeForm
    { formDescription = look "description"
    , formProjectId = look "projectId"
    , formTitle = look "title"
    }
  where
    look k = case lookupMaybe k f of
      Right (Just v) -> Just . encodeUtf8 $ v
      _ -> Nothing

createNode ::
  PostNodeForm ->
  UTCTime ->
  ReaderT SqlBackend IO (Either InsertNodeResult (Entity M.Node))
createNode form now = runEitherT $ do
  pyl <- hoistEither . validateForm $ form
  pr <-
    lift (queryProject . projectId $ pyl)
      >>= hoistMaybe ProjectNotFound
  st <-
    lift (queryStatus "active")
      >>= hoistMaybe MissingStatus
  tp <-
    lift (queryType "work")
      >>= hoistMaybe MissingType
  let nd = toNode now pyl pr st tp
  ky <- lift . insert $ nd
  pure $ Entity ky nd

toNode ::
  UTCTime ->
  PostNodePayload ->
  Entity M.Project ->
  Entity M.NodeStatus ->
  Entity M.NodeType ->
  M.Node
toNode now pyl pr st tp =
  M.Node
    { M.nodeCreated = now
    , M.nodeDeleted = Nothing
    , M.nodeDescription = unpack . description $ pyl
    , M.nodeNodeStatusId = entityKey st
    , M.nodeNodeTypeId = entityKey tp
    , M.nodeProjectId = entityKey pr
    , M.nodeTitle = unpack . title $ pyl
    , M.nodeUpdated = now
    }

validateForm :: PostNodeForm -> Either InsertNodeResult PostNodePayload
validateForm fm = runValidation FailValidation $ do
  dscr <-
    formDescription fm
      .$ decodeUtf8
      >>= isThere "Description is required"
      >>= isNotEmpty "Description cannot be empty"
  pid <-
    formProjectId fm
      .$ (unpack . decodeUtf8)
      >>= isThere "Project id is required"
      >>= isNotEmpty "Project id cannot be empty"
      >>= valRead "Project id must be valid integer"
  ttl <-
    formTitle fm
      .$ decodeUtf8
      >>= isThere "Title cannot be empty"
  return $ PostNodePayload <$> dscr <*> pid <*> ttl

queryProject :: Int64 -> ReaderT SqlBackend IO (Maybe (Entity M.Project))
queryProject pid = do
  prj <- select $ do
    p <- from $ table @M.Project
    where_ $ p.id ==. (val . toSqlKey @M.Project $ pid)
    limit 1
    pure p
  return . listToMaybe $ prj

queryStatus :: Text -> ReaderT SqlBackend IO (Maybe (Entity M.NodeStatus))
queryStatus st = do
  ns <- select $ do
    s <- from $ table @M.NodeStatus
    where_ $ s.nodeStatusId ==. (val . unpack $ st)
    limit 1
    pure s
  return . listToMaybe $ ns

queryType :: Text -> ReaderT SqlBackend IO (Maybe (Entity M.NodeType))
queryType tpe = do
  tp <- select $ do
    t <- from $ table @M.NodeType
    where_ $ t.nodeTypeId ==. (val . unpack $ tpe)
    limit 1
    pure t
  return . listToMaybe $ tp

handler ::
  Form ->
  AppM (Headers '[Header "Location" Text] CreatedNode)
handler form = do
  now <- liftIO getCurrentTime
  rslt <- runDb . createNode (formToPostNodeForm form) $ now
  case rslt of
    Left (FailValidation es) -> throwError err422 {errBody = errJson es}
    Left ProjectNotFound ->
      throwError err404 {errBody = errJson ["Project not found" :: Text]}
    Left MissingStatus -> throwError err500 {errBody = serverErr}
    Left MissingType -> throwError err500 {errBody = serverErr}
    Right (Entity ky _) ->
      let nid = fromSqlKey ky
       in pure $
            addHeader
              (nodeResourceLink nid)
              (CreatedNode nid)
  where
    errJson es = encode . object $ ["error" .= es]
    serverErr = errJson ["Internal server error" :: Text]
