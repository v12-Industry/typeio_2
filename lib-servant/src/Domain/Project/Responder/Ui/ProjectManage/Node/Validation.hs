{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Validation where

import Common.Validation (ValidationErr, isEq, runValidation, (.$))
import Control.Monad.Trans.Either (EitherT, hoistEither)
import Data.Int (Int64)
import Database.Persist.Sql (Entity (..), fromSqlKey)
import qualified Domain.Project.Model as M

nodeInProject ::
  Int64 ->
  Entity M.Node ->
  Either [ValidationErr] (Entity M.Node)
nodeInProject pid (Entity k e) = runValidation id $ do
  _ <-
    Just e
      .$ (fromSqlKey . M.nodeProjectId)
      >>= isEq pid "Invalid state. Node is not part of project"
  return . Just . Entity k $ e

validateNodeProjectId ::
  Monad m =>
  Int64 ->
  Entity M.Node ->
  EitherT [ValidationErr] m (Entity M.Node)
validateNodeProjectId pid = hoistEither . nodeInProject pid
