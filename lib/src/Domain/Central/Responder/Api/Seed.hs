{-# LANGUAGE OverloadedStrings #-}

module Domain.Central.Responder.Api.Seed where

import Control.Monad (forM_)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (ReaderT)
import qualified Data.Map.Strict as M
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist (insert, insertUnique, insert_, selectFirst, (==.))
import Database.Persist.Postgresql (ConnectionPool)
import Database.Persist.Sql (SqlBackend, runSqlPool)
import Domain.Project.Model
  ( Dependency (..)
  , Node (..)
  , NodeStatus (..)
  , NodeStatusId
  , NodeType (..)
  , NodeTypeId
  , ProjectId
  )
import qualified Domain.Project.Model as M
import Network.HTTP.Types (status200)
import Network.Wai (Response, ResponseReceived, responseLBS)

handleSeedDatabase :: ConnectionPool -> (Response -> IO ResponseReceived) -> IO ResponseReceived
handleSeedDatabase pool respond = do
  flip runSqlPool pool $ do
    mapM_ insertUnique nodeStatuses
    mapM_ insertUnique nodeTypes
    seedDemoProject
  respond $
    responseLBS
      status200
      [("Content-Type", "application/json")]
      "Database seeded successfully"

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

demoRootTitle :: String
demoRootTitle = "Public API launch"

demoWork :: [(Char, String, String)]
demoWork =
  [ ('A', "Publish the launch post", "Announcement, once there is something to announce.")
  , ('B', "Ship the mobile client", "The client everyone is actually waiting for.")
  , ('C', "Stabilise the public API", "Freeze the surface and stop breaking callers.")
  , ('D', "Run the beta programme", "A dozen friendly teams, in production.")
  , ('E', "Finish the auth service", "Tokens, refresh, revocation.")
  , ('F', "Open the partner sandbox", "Somewhere partners can integrate safely.")
  , ('G', "Write the integration guide", "The document a partner reads first.")
  ]

demoDependencies :: [(Char, Char)]
demoDependencies =
  [ ('A', 'D')
  , ('D', 'E')
  , ('B', 'C')
  , ('C', 'E')
  , ('F', 'G')
  , ('F', 'C')
  ]

seedDemoProject :: MonadIO m => ReaderT SqlBackend m ()
seedDemoProject = do
  existing <- selectFirst [M.NodeTitle ==. demoRootTitle] []
  case existing of
    Just _ -> pure ()
    Nothing -> do
      now <- liftIO getCurrentTime
      projectKey <- insert M.Project
      let node = demoNode now projectKey
      _ <-
        insert
          . node rootType demoRootTitle
          $ "Everything the launch is waiting on."
      workKeys <-
        mapM
          (\(_, title, desc) -> insert (node workType title desc))
          demoWork
      let keyOf = M.fromList (zip [t | (t, _, _) <- demoWork] workKeys)
      forM_ demoDependencies $ \(dependent, dependency) ->
        forM_ ((,) <$> M.lookup dependent keyOf <*> M.lookup dependency keyOf) $
          \(a, b) -> insert_ (Dependency a b)
  where
    rootType = M.NodeTypeKey "project_root"
    workType = M.NodeTypeKey "work"

demoNode ::
  UTCTime ->
  ProjectId ->
  NodeTypeId ->
  String ->
  String ->
  Node
demoNode now projectKey typeKey title desc =
  M.Node
    { M.nodeCreated = now
    , M.nodeDeleted = Nothing
    , M.nodeDescription = desc
    , M.nodeNodeStatusId = activeStatus
    , M.nodeNodeTypeId = typeKey
    , M.nodeProjectId = projectKey
    , M.nodeTitle = title
    , M.nodeUpdated = now
    }

activeStatus :: NodeStatusId
activeStatus = M.NodeStatusKey "active"
