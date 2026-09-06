{-# LANGUAGE OverloadedStrings #-}

{- | Shared infrastructure for the @integration@ test-suite: starting a
disposable Postgres container, migrating and seeding it, and tearing
it down again. One container is meant to be started per suite run
(via Hspec's 'Test.Hspec.aroundAll', not 'Test.Hspec.around') and
reused across every test in that run, with 'resetBetweenTests'
truncating mutable data between individual tests.

See @docs/solution-proposals/integration-testing.md@ (§4-§6) for the
reasoning behind each choice here.
-}
module Integration.Support
  ( withTestDatabase
  , resetBetweenTests
  , seedProjectWithRootNode
  , seedWorkNode
  , seedDependency
  ) where

import Config.Db (DbConfig (..))
import Control.Exception (ErrorCall (..), throwIO)
import Control.Monad.Cont (runContT)
import Control.Monad.IO.Class (liftIO)
import Data.Function ((&))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import Data.Time (getCurrentTime)
import Database.Persist (Entity (..), Key, insert, insertUnique, insert_, selectList, (==.))
import Database.Persist.Sql (ConnectionPool, rawExecute, runSqlPool)
import qualified Domain.Central.Responder.Api.Seed as Seed
import qualified Domain.Project.Model as M
import Environment.Db (withPool)
import System.Directory (makeAbsolute)
import qualified TestContainers.Hspec as TC

{- | Credentials for the disposable container. The official Postgres
image creates a database named after @POSTGRES_USER@ when
@POSTGRES_DB@ isn't set, so this value doubles as the database name
too -- see 'testDbConfig'.
-}
testDbUser :: Text
testDbUser = "typeio_test"

testDbPassword :: Text
testDbPassword = "typeio_test"

{- | Starts a @postgres:15@ container (same version
@local/script/start-postgres.sh@ uses), migrated and seeded before
the action ever sees it, and hands the action a ready
'ConnectionPool'. The container is torn down once the action
returns.

Migrations run *inside* the container itself, not from this Haskell
process: 'pgRequest' bind-mounts the real @migrations/@ directory
plus @test-integration\/docker\/apply-migrations.sh@ into
@\/docker-entrypoint-initdb.d@, the official Postgres image's own
"run this once, automatically, on first startup" convention. That
script applies @migrations\/*.up.sql@ with @psql@ (already in the
image). Deliberately not the @migrate@ CLI here -- this way,
running @cabal test integration@ only needs Docker, not a
separately-installed migration tool on top of it.
-}
withTestDatabase :: (ConnectionPool -> IO ()) -> IO ()
withTestDatabase action = do
  req <- pgRequest
  TC.withContainers (TC.run req) $ \container -> do
    let (dbHost, dbPort') = TC.containerAddress container 5432
    runContT (withPool $ testDbConfig dbHost dbPort') $ \pool -> do
      seedReferenceData pool
      action pool

pgRequest :: IO TC.ContainerRequest
pgRequest = do
  migrationsDir <- makeAbsolute "migrations"
  migrateScript <- makeAbsolute "test-integration/docker/apply-migrations.sh"
  pure $
    TC.containerRequest (TC.fromTag "postgres:15")
      & TC.setExpose [5432]
      & TC.setEnv
        [ ("POSTGRES_USER", testDbUser)
        , ("POSTGRES_PASSWORD", testDbPassword)
        ]
      & TC.setVolumeMounts
        [ (T.pack migrationsDir, "/docker-entrypoint-initdb.d/migrations:ro")
        , (T.pack migrateScript, "/docker-entrypoint-initdb.d/apply-migrations.sh:ro")
        ]
      & TC.setWaitingFor waitUntilReady
  where
    -- Both conditions matter: on a first-time start with initdb.d
    -- scripts, Postgres logs "ready to accept connections" once for an
    -- internal-only setup instance *before* running init scripts, then
    -- restarts into the real server afterward. The log-line check alone
    -- could match that first, too-early instance -- but the mapped TCP
    -- port isn't actually listening until the final restart, so ANDing
    -- it with waitUntilMappedPortReachable rules that out.
    waitUntilReady =
      mconcat
        [ TC.waitForLogLine TC.Stderr (TL.isInfixOf "database system is ready to accept connections")
        , TC.waitUntilMappedPortReachable 5432
        ]

testDbConfig :: Text -> Int -> DbConfig
testDbConfig dbHost dbPort' =
  DbConfig
    { database = T.unpack testDbUser
    , host = T.unpack dbHost
    , password = T.unpack testDbPassword
    , dbPort = show dbPort'
    , poolCount = 5
    , schema = "project"
    , user = T.unpack testDbUser
    }

seedReferenceData :: ConnectionPool -> IO ()
seedReferenceData pool = flip runSqlPool pool $ do
  mapM_ insertUnique Seed.nodeStatuses
  mapM_ insertUnique Seed.nodeTypes

{- | Clears every table a test might have written to, without touching
the reference data 'seedReferenceData' inserted once at container
startup. Truncating all three together (rather than deleting in
dependency order) sidesteps FK ordering entirely.
-}
truncateTestData :: ConnectionPool -> IO ()
truncateTestData pool =
  flip runSqlPool pool $
    rawExecute
      "TRUNCATE project.dependency, project.node, project.project RESTART IDENTITY CASCADE"
      []

{- | Hspec @beforeWith@-shaped hook: truncate mutable tables before each
test, then hand the same pool through unchanged. Truncating instead
of wrapping each test in a rolled-back transaction is deliberate --
responders commit their own transaction via 'runSqlPool', so there's
no outer transaction for a test to roll back (see the proposal's §5).
-}
resetBetweenTests :: ConnectionPool -> IO ConnectionPool
resetBetweenTests pool = truncateTestData pool >> pure pool

{- | Minimal fixture every write-responder test needs: a bare 'M.Project'
and a root 'M.Node' attached to it (status @active@, type
@project_root@ -- both from 'seedReferenceData'). Centralized here
since every mutating-responder integration test needs the same
starting point.
-}
seedProjectWithRootNode :: ConnectionPool -> IO (Key M.Project, Key M.Node)
seedProjectWithRootNode pool = flip runSqlPool pool $ do
  now <- liftIO getCurrentTime
  projectKey <- insert M.Project
  activeStatus <- selectList [M.NodeStatusNodeStatusId ==. "active"] []
  rootType <- selectList [M.NodeTypeNodeTypeId ==. "project_root"] []
  statusKey <- keyOrErr "NodeStatus \"active\"" activeStatus
  typeKey <- keyOrErr "NodeType \"project_root\"" rootType
  rootKey <-
    insert
      M.Node
        { M.nodeCreated = now
        , M.nodeDeleted = Nothing
        , M.nodeDescription = "Root node"
        , M.nodeNodeStatusId = statusKey
        , M.nodeNodeTypeId = typeKey
        , M.nodeProjectId = projectKey
        , M.nodeTitle = "Root"
        , M.nodeUpdated = now
        }
  pure (projectKey, rootKey)
  where
    keyOrErr label rows = case rows of
      (e : _) -> pure (entityKey e)
      [] ->
        liftIO . throwIO . ErrorCall $
          "seedProjectWithRootNode: expected seeded " <> label <> " but found none"

{- | An ordinary (non-root) 'M.Node' on an existing project: status
@active@, type @work@. Companion to 'seedProjectWithRootNode' for
tests that need a graph rather than a single node -- the two node
types render differently, so a test asserting on either needs
both present.
-}
seedWorkNode :: ConnectionPool -> Key M.Project -> String -> IO (Key M.Node)
seedWorkNode pool projectKey title = flip runSqlPool pool $ do
  now <- liftIO getCurrentTime
  activeStatus <- selectList [M.NodeStatusNodeStatusId ==. "active"] []
  workType <- selectList [M.NodeTypeNodeTypeId ==. "work"] []
  statusKey <- keyOrErr "NodeStatus \"active\"" activeStatus
  typeKey <- keyOrErr "NodeType \"work\"" workType
  insert
    M.Node
      { M.nodeCreated = now
      , M.nodeDeleted = Nothing
      , M.nodeDescription = "Work node"
      , M.nodeNodeStatusId = statusKey
      , M.nodeNodeTypeId = typeKey
      , M.nodeProjectId = projectKey
      , M.nodeTitle = title
      , M.nodeUpdated = now
      }
  where
    keyOrErr label rows = case rows of
      (e : _) -> pure (entityKey e)
      [] ->
        liftIO . throwIO . ErrorCall $
          "seedWorkNode: expected seeded " <> label <> " but found none"

{- | Record that @dependent@ is waiting on @dependency@ being completed
first. Argument order follows the relationship, not the column names:
@project.dependency@ stores the dependent in @node_id@ and the
dependency in @to_node_id@ (see
@docs\/development\/backend\/database-schema.md@), which is easy to
get backwards from the column names alone.
-}
seedDependency :: ConnectionPool -> Key M.Node -> Key M.Node -> IO ()
seedDependency pool dependent dependency =
  flip runSqlPool pool
    . insert_
    $ M.Dependency
      { M.dependencyNodeId = dependent
      , M.dependencyToNodeId = dependency
      }
