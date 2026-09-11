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
    seedDemoProjects
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

data DemoWork = DemoWork
  { dwKey :: Char
  , dwTitle :: String
  , dwDescription :: String
  , dwStatus :: String
  }

data DemoProject = DemoProject
  { dpTitle :: String
  , dpDescription :: String
  , dpWork :: [DemoWork]
  , dpDependencies :: [(Char, Char)]
  }

demoProjects :: [DemoProject]
demoProjects =
  [ apiLaunch
  , warehouseMigration
  , designSystemRefresh
  , billingRewrite
  , mobileRelaunch
  , complianceAudit
  ]

demoRootTitle :: String
demoRootTitle = dpTitle apiLaunch

demoWork :: [DemoWork]
demoWork = dpWork apiLaunch

demoDependencies :: [(Char, Char)]
demoDependencies = dpDependencies apiLaunch

apiLaunch :: DemoProject
apiLaunch =
  DemoProject
    { dpTitle = "Public API launch"
    , dpDescription = "Everything the launch is waiting on."
    , dpWork =
        [ DemoWork 'A' "Publish the launch post" "Announcement, once there is something to announce." "active"
        , DemoWork 'B' "Ship the mobile client" "The client everyone is actually waiting for." "active"
        , DemoWork 'C' "Stabilise the public API" "Freeze the surface and stop breaking callers." "active"
        , DemoWork 'D' "Run the beta programme" "A dozen friendly teams, in production." "active"
        , DemoWork 'E' "Finish the auth service" "Tokens, refresh, revocation." "active"
        , DemoWork 'F' "Open the partner sandbox" "Somewhere partners can integrate safely." "active"
        , DemoWork 'G' "Write the integration guide" "The document a partner reads first." "active"
        ]
    , dpDependencies =
        [ ('A', 'D')
        , ('D', 'E')
        , ('B', 'C')
        , ('C', 'E')
        , ('F', 'G')
        , ('F', 'C')
        ]
    }

warehouseMigration :: DemoProject
warehouseMigration =
  DemoProject
    { dpTitle = "Warehouse migration"
    , dpDescription = "One long chain, most of it already behind us."
    , dpWork =
        [ DemoWork 'A' "Decommission the old warehouse" "The last step, once nothing reads from it." "open"
        , DemoWork 'B' "Cut reporting over" "Point every dashboard at the new tables." "open"
        , DemoWork 'C' "Backfill the history" "Ten years of rows, in batches." "active"
        , DemoWork 'D' "Mirror the write path" "Dual-write until the backfill catches up." "closed"
        , DemoWork 'E' "Model the new schema" "Star schema, agreed with the analysts." "closed"
        , DemoWork 'F' "Stand up the cluster" "Provisioned, monitored, and paid for." "closed"
        ]
    , dpDependencies =
        [ ('A', 'B')
        , ('B', 'C')
        , ('C', 'D')
        , ('D', 'E')
        , ('E', 'F')
        ]
    }

designSystemRefresh :: DemoProject
designSystemRefresh =
  DemoProject
    { dpTitle = "Design system refresh"
    , dpDescription = "Independent pieces of work that wait on nothing."
    , dpWork =
        [ DemoWork 'A' "Agree the colour tokens" "One palette, named and documented." "closed"
        , DemoWork 'B' "Rebuild the button set" "Every variant, one component." "active"
        , DemoWork 'C' "Document the spacing scale" "The scale everything else is measured in." "open"
        , DemoWork 'D' "Audit the icon set" "Find the duplicates and the strays." "open"
        , DemoWork 'E' "Ship a dark theme toggle" "Dropped in favour of following the system." "rejected"
        ]
    , dpDependencies = []
    }

billingRewrite :: DemoProject
billingRewrite =
  DemoProject
    { dpTitle = "Billing rewrite"
    , dpDescription = "A diamond: two streams over one shared foundation."
    , dpWork =
        [ DemoWork 'A' "Invoice the new plans" "Monthly and annual, prorated." "open"
        , DemoWork 'B' "Migrate the legacy plans" "Everyone still on the old price book." "active"
        , DemoWork 'C' "Rebuild the ledger" "Double-entry, and reconciled nightly." "active"
        , DemoWork 'D' "Retire the coupon engine" "Superseded by the discount rules." "rejected"
        ]
    , dpDependencies =
        [ ('A', 'C')
        , ('B', 'C')
        ]
    }

mobileRelaunch :: DemoProject
mobileRelaunch =
  DemoProject
    { dpTitle = "Mobile relaunch"
    , dpDescription = "The large one: several streams over a shared bottleneck."
    , dpWork =
        [ DemoWork 'A' "Submit to the app stores" "Two review queues, one release note." "open"
        , DemoWork 'B' "Run the field trial" "Fifty devices, four weeks." "open"
        , DemoWork 'C' "Rebuild the onboarding flow" "Three screens instead of seven." "active"
        , DemoWork 'D' "Rewrite the sync engine" "Offline-first, conflict-aware." "active"
        , DemoWork 'E' "Replace the crash reporter" "The one that actually symbolicates." "closed"
        , DemoWork 'F' "Agree the offline rules" "What the app may do with no network." "closed"
        , DemoWork 'G' "Port the design system" "The tokens, on the phone." "active"
        , DemoWork 'H' "Rework the settings screen" "Everything nobody could find." "open"
        , DemoWork 'I' "Drop the tablet layout" "Not enough users to carry the cost." "rejected"
        , DemoWork 'J' "Instrument the funnel" "Know where people give up." "active"
        , DemoWork 'K' "Refresh the marketing site" "The page the store listing points at." "open"
        , DemoWork 'L' "Pick the release train" "Fortnightly, with a cut-off everyone believes." "closed"
        ]
    , dpDependencies =
        [ ('A', 'B')
        , ('B', 'C')
        , ('B', 'D')
        , ('C', 'G')
        , ('D', 'F')
        , ('D', 'E')
        , ('H', 'G')
        , ('J', 'D')
        , ('K', 'C')
        , ('A', 'L')
        ]
    }

complianceAudit :: DemoProject
complianceAudit =
  DemoProject
    { dpTitle = "Compliance audit"
    , dpDescription = "A project nobody has broken into work yet."
    , dpWork = []
    , dpDependencies = []
    }

seedDemoProjects :: MonadIO m => ReaderT SqlBackend m ()
seedDemoProjects = mapM_ seedDemoProject demoProjects

seedDemoProject :: MonadIO m => DemoProject -> ReaderT SqlBackend m ()
seedDemoProject project = do
  existing <- selectFirst [M.NodeTitle ==. dpTitle project] []
  case existing of
    Just _ -> pure ()
    Nothing -> do
      now <- liftIO getCurrentTime
      projectKey <- insert M.Project
      let node = demoNode now projectKey
      _ <-
        insert
          . node rootType activeStatus (dpTitle project)
          $ dpDescription project
      workKeys <-
        mapM
          ( \w ->
              insert
                ( node
                    workType
                    (M.NodeStatusKey (dwStatus w))
                    (dwTitle w)
                    (dwDescription w)
                )
          )
          (dpWork project)
      let keyOf = M.fromList (zip (map dwKey (dpWork project)) workKeys)
      forM_ (dpDependencies project) $ \(dependent, dependency) ->
        forM_ ((,) <$> M.lookup dependent keyOf <*> M.lookup dependency keyOf) $
          \(a, b) -> insert_ (Dependency a b)
  where
    rootType = M.NodeTypeKey "project_root"
    workType = M.NodeTypeKey "work"

demoNode ::
  UTCTime ->
  ProjectId ->
  NodeTypeId ->
  NodeStatusId ->
  String ->
  String ->
  Node
demoNode now projectKey typeKey statusKey title desc =
  M.Node
    { M.nodeCreated = now
    , M.nodeDeleted = Nothing
    , M.nodeDescription = desc
    , M.nodeNodeStatusId = statusKey
    , M.nodeNodeTypeId = typeKey
    , M.nodeProjectId = projectKey
    , M.nodeTitle = title
    , M.nodeUpdated = now
    }

activeStatus :: NodeStatusId
activeStatus = M.NodeStatusKey "active"
