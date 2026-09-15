{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Domain.Project.Responder.Ui.ProjectCreate.Submit where

import App.Api (HxRedirect)
import App.Env (AppM, runDb)
import App.Link (projectIndexLink)
import Common.Validation
  ( ValidationErr
  , isNotEmpty
  , isThere
  , runValidation
  , (.$)
  )
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either (hoistEither, hoistMaybe, runEitherT)
import Data.Aeson
  ( ToJSON
  , encode
  , object
  , toJSON
  , (.=)
  )
import Data.ByteString (ByteString, toStrict)
import Data.Maybe (listToMaybe)
import qualified Data.Text as T (Text, unpack)
import Data.Text.Encoding (decodeUtf8)
import Data.Time (UTCTime, getCurrentTime)
import Database.Esqueleto.Experimental
  ( from
  , insert
  , limit
  , select
  , table
  , val
  , where_
  , (==.)
  )
import Database.Persist (Entity (..), Key)
import Database.Persist.Sql (SqlBackend)
import qualified Domain.Project.Model as M
  ( Node (..)
  , NodeStatus (..)
  , NodeType (..)
  , Project (..)
  )
import qualified Domain.Project.Responder.Ui.ProjectCreate.View as CreateView
import qualified Domain.Project.Responder.Ui.ProjectCreate.View as V (AddProjectForm (..))
import Network.HTTP.Types (HeaderName)
import Servant (addHeader, noHeader)
import Web.FormUrlEncoded (Form, lookupMaybe)

data ProjectAddResult
  = MissingNodeStatus
  | MissingNodeType
  | FormValidationFail [ValidationErr]

data LocationResponseHeader = LocationResponseHeader
  { path :: String
  , target :: String
  }

instance ToJSON LocationResponseHeader where
  toJSON (LocationResponseHeader p t) =
    object ["path" .= p, "target" .= t]

data AddProjectPayload = AddProjectPayload
  { description :: T.Text
  , title :: T.Text
  }

createProject ::
  V.AddProjectForm ->
  UTCTime ->
  ReaderT SqlBackend IO (Either ProjectAddResult (Key M.Node))
createProject form now = runEitherT $ do
  pyld <- hoistEither . buildPayload $ form
  st <-
    lift (queryStatus "active")
      >>= hoistMaybe MissingNodeStatus
  tp <-
    lift (queryType "project_root")
      >>= hoistMaybe MissingNodeType
  pkey <- lift . insert $ M.Project
  let nd =
        M.Node
          { M.nodeCreated = now
          , M.nodeDeleted = Nothing
          , M.nodeDescription = T.unpack . description $ pyld
          , M.nodeNodeStatusId = entityKey st
          , M.nodeNodeTypeId = entityKey tp
          , M.nodeProjectId = pkey
          , M.nodeTitle = T.unpack . title $ pyld
          , M.nodeUpdated = now
          }
  lift . insert $ nd

formToAddProjectForm :: Form -> V.AddProjectForm
formToAddProjectForm f =
  V.AddProjectForm
    { V.description = look "description"
    , V.title = look "title"
    }
  where
    look k = case lookupMaybe k f of
      Right (Just v) -> Just v
      _ -> Nothing

redirectHeader :: (HeaderName, ByteString)
redirectHeader =
  let hd =
        encode $
          LocationResponseHeader
            { path = T.unpack projectIndexLink
            , target = "#container"
            }
   in ("Hx-Location", toStrict hd)

buildPayload :: V.AddProjectForm -> Either ProjectAddResult AddProjectPayload
buildPayload fm = runValidation FormValidationFail $ do
  dscr <-
    V.description fm
      .$ id
      >>= isThere "Description is required"
      >>= isNotEmpty "Description cannot be empty"
  ttl <-
    V.title fm
      .$ id
      >>= isThere "Title is required"
      >>= isNotEmpty "Title cannot be empty"
  return $ AddProjectPayload <$> dscr <*> ttl

queryStatus ::
  String ->
  ReaderT SqlBackend IO (Maybe (Entity M.NodeStatus))
queryStatus st = do
  ns <- select $ do
    s <- from $ table @M.NodeStatus
    where_ $ s.nodeStatusId ==. val st
    limit 1
    pure s
  return . listToMaybe $ ns

queryType ::
  String ->
  ReaderT SqlBackend IO (Maybe (Entity M.NodeType))
queryType tp = do
  ns <- select $ do
    t <- from $ table @M.NodeType
    where_ $ t.nodeTypeId ==. val tp
    limit 1
    pure t
  return . listToMaybe $ ns

handler :: Form -> AppM HxRedirect
handler f = do
  let form = formToAddProjectForm f
  now <- liftIO getCurrentTime
  rslt <- runDb . createProject form $ now
  pure $ case rslt of
    Right _ -> addHeader (decodeUtf8 (snd redirectHeader)) mempty
    Left (FormValidationFail es) ->
      noHeader . CreateView.projectCreateVwTemplate form $ es
    Left _ ->
      noHeader . CreateView.projectCreateVwTemplate form $ ["Could not create the project"]
