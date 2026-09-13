{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Api.Node.Get where

import Control.Monad.Reader (ReaderT)
import Data.Aeson
  ( ToJSON
  , encode
  , object
  , toJSON
  , (.=)
  )
import Data.Int (Int64)
import Data.Time (UTCTime)
import Database.Esqueleto.Experimental (from, select, table)
import Database.Persist (Entity (..))
import Database.Persist.Sql (ConnectionPool, SqlBackend, fromSqlKey, runSqlPool)
import qualified Domain.Project.Model as M
  ( Node (..)
  , nodeCreated
  , nodeDeleted
  , nodeDescription
  , nodeNodeStatusId
  , nodeNodeTypeId
  , nodeProjectId
  , nodeTitle
  , nodeUpdated
  , unNodeStatusKey
  , unNodeTypeKey
  )
import Network.HTTP.Types (status200)
import Network.Wai (Response, ResponseReceived, responseLBS)

data Node = Node
  { created :: UTCTime
  , deleted :: Maybe UTCTime
  , description :: String
  , nodeId :: Int64
  , nodeStatusId :: String
  , nodeTypeId :: String
  , projectId :: Int64
  , title :: String
  , updated :: UTCTime
  }

instance ToJSON Node where
  toJSON (Node c d desc nId nsId ntId pId t u) =
    object
      [ "created" .= c
      , "deleted" .= d
      , "description" .= desc
      , "nodeId" .= nId
      , "nodeStatusId" .= nsId
      , "nodeTypeId" .= ntId
      , "projectId" .= pId
      , "title" .= t
      , "updated" .= u
      ]

handleGetNodes :: ConnectionPool -> (Response -> IO ResponseReceived) -> IO ResponseReceived
handleGetNodes pl respond = do
  ns <- encode <$> runSqlPool listNodes pl
  respond $ responseLBS status200 [("Content-Type", "application/json")] ns

listNodes :: ReaderT SqlBackend IO [Node]
listNodes = map toSchema <$> query
  where
    query = select $ from $ table @M.Node
    toSchema (Entity k v) =
      Node
        { created = M.nodeCreated v
        , deleted = M.nodeDeleted v
        , description = M.nodeDescription v
        , nodeId = fromSqlKey k
        , nodeStatusId = M.unNodeStatusKey . M.nodeNodeStatusId $ v
        , nodeTypeId = M.unNodeTypeKey . M.nodeNodeTypeId $ v
        , projectId = fromSqlKey . M.nodeProjectId $ v
        , title = M.nodeTitle v
        , updated = M.nodeUpdated v
        }
