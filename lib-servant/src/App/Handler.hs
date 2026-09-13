{-# LANGUAGE OverloadedStrings #-}

module App.Handler
  ( FieldUpdateErr (..)
  , htmlError
  , nodeForUpdate
  , renderNode
  , updateNodeField
  ) where

import App.Env (AppM, runDb)
import Control.Monad.Error.Class (throwError)
import Control.Monad.Reader (ReaderT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either (EitherT, firstEitherT, hoistMaybe, runEitherT)
import Data.Int (Int64)
import Data.Text (Text)
import Database.Persist (Entity (..))
import Database.Persist.Sql (SqlBackend)
import qualified Domain.Project.Model as M
import Domain.Project.Responder.Ui.ProjectManage.Node.Query (queryNode)
import Domain.Project.Responder.Ui.ProjectManage.Node.Validation
  ( nodeInProject
  , validateNodeProjectId
  )
import Lucid (Html, renderBS)
import Servant (ServerError, err404, err422, errBody, errHeaders)

data FieldUpdateErr
  = FieldInvalid [Text]
  | FieldNodeMissing

renderNode ::
  Int64 ->
  Int64 ->
  Html () ->
  ([Text] -> Html ()) ->
  (Entity M.Node -> AppM (Html ())) ->
  AppM (Html ())
renderNode pid nid missing invalid found = do
  mnde <- runDb (queryNode nid)
  case mnde of
    Nothing -> pure missing
    Just ent -> either (pure . invalid) found (nodeInProject pid ent)

nodeForUpdate ::
  Int64 ->
  Int64 ->
  EitherT FieldUpdateErr (ReaderT SqlBackend IO) (Entity M.Node)
nodeForUpdate pid nid =
  lift (queryNode nid)
    >>= hoistMaybe FieldNodeMissing
    >>= firstEitherT FieldInvalid . validateNodeProjectId pid

updateNodeField ::
  Html () ->
  ([Text] -> Html ()) ->
  Html () ->
  EitherT FieldUpdateErr (ReaderT SqlBackend IO) () ->
  AppM (Html ())
updateNodeField missing invalid ok act = do
  rslt <- runDb (runEitherT act)
  case rslt of
    Left (FieldInvalid es) -> throwError (htmlError err422 (invalid es))
    Left FieldNodeMissing -> throwError (htmlError err404 missing)
    Right () -> pure ok

htmlError :: ServerError -> Html () -> ServerError
htmlError er tpl =
  er
    { errBody = renderBS tpl
    , errHeaders = [("Content-Type", "text/html")]
    }
