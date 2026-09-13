{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Query where

import Control.Monad.Reader (ReaderT)
import Data.Int (Int64)
import Data.Maybe (listToMaybe)
import Database.Esqueleto.Experimental
import qualified Domain.Project.Model as M

queryNode :: Int64 -> ReaderT SqlBackend IO (Maybe (Entity M.Node))
queryNode nid = do
  ns <- select $ do
    n <- from $ table @M.Node
    where_ (n.id ==. val nkey)
    limit 1
    pure n
  return . listToMaybe $ ns
  where
    nkey = toSqlKey @M.Node nid

queryProject :: Int64 -> ReaderT SqlBackend IO (Maybe (Entity M.Project))
queryProject pid = do
  ps <- select $ do
    p <- from $ table @M.Project
    where_ (p.id ==. val (toSqlKey @M.Project pid))
    limit 1
    pure p
  return . listToMaybe $ ps

queryNodeStatus :: String -> ReaderT SqlBackend IO (Maybe (Entity M.NodeStatus))
queryNodeStatus sid = do
  ss <- select $ do
    s <- from $ table @M.NodeStatus
    where_ (s.nodeStatusId ==. val sid)
    limit 1
    pure s
  return . listToMaybe $ ss

queryNodeType :: String -> ReaderT SqlBackend IO (Maybe (Entity M.NodeType))
queryNodeType tid = do
  ts <- select $ do
    t <- from $ table @M.NodeType
    where_ (t.nodeTypeId ==. val tid)
    limit 1
    pure t
  return . listToMaybe $ ts
