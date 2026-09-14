{-# LANGUAGE OverloadedStrings #-}

module Domain.Central.Responder.Api.Seed where

import App.Env (AppM, runDb)
import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Reader (ReaderT)
import Data.Text (Text)
import Database.Persist (insertUnique)
import Database.Persist.Sql (SqlBackend)
import Domain.Project.Model (NodeStatus (..), NodeType (..))

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

handler :: AppM Text
handler = do
  runDb seedReferenceData
  pure "Database seeded successfully"
