{-# LANGUAGE OverloadedStrings #-}

module Domain.Central.Responder.Api.Seed where

import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Reader (ReaderT)
import Database.Persist (insertUnique)
import Database.Persist.Postgresql (ConnectionPool)
import Database.Persist.Sql (SqlBackend, runSqlPool)
import Domain.Project.Model (NodeStatus (..), NodeType (..))
import Network.HTTP.Types (status200)
import Network.Wai (Response, ResponseReceived, responseLBS)

handleSeedDatabase :: ConnectionPool -> (Response -> IO ResponseReceived) -> IO ResponseReceived
handleSeedDatabase pool respond = do
  runSqlPool seedReferenceData pool
  respond $
    responseLBS
      status200
      [("Content-Type", "application/json")]
      "Database seeded successfully"

seedReferenceData :: MonadIO m => ReaderT SqlBackend m ()
seedReferenceData = do
  mapM_ insertUnique nodeStatuses
  mapM_ insertUnique nodeTypes

nodeTypes :: [NodeType]
nodeTypes =
  [ NodeType "project_root"
  , NodeType "work"
  ]

nodeStatuses :: [NodeStatus]
nodeStatuses =
  [ NodeStatus "active"
  , NodeStatus "closed"
  , NodeStatus "open"
  , NodeStatus "rejected"
  ]
