{-# LANGUAGE OverloadedStrings #-}

{- | Shared infrastructure for the @integration@ test-suite: starting a
disposable Postgres container, building the application over it,
driving HTTP requests at it, and tearing it all down again.

One container is meant to be started per suite run (via Hspec's
'Test.Hspec.aroundAll', not 'Test.Hspec.around') and reused across
every test in that run, with 'resetBetweenTests' truncating mutable
data between individual tests.

Tests address the application by URL rather than by calling a
handler, so what they exercise includes the routing: a spec whose
path or parameter name is wrong fails rather than quietly passing
against a function nothing would reach. See
@docs/development/integration-testing.md@ for the shape, and
@docs/solution-proposals/integration-testing.md@ (§4-§6) for the
reasoning behind the container choices here.
-}
module Integration.Support
  ( TestApp (..)
  , SResponse
  , withTestApp
  , resetBetweenTests
  , seedProjectWithRootNode
  , seedWorkNode
  , seedDependency
  , httpGet
  , httpPost
  , httpPut
  , formBody
  , bodyOf
  , headerOf
  , statusOf
  , shouldContainStr
  , shouldNotContainStr
  , countStr
  , indexOfStr
  ) where

import App.Env (Env (..))
import App.Server (app)
import Config.App (AppConfig (..), EnvironmentName (Local))
import Config.Db (DbConfig (..))
import Config.Web (WebConfig (..))
import Control.Exception (ErrorCall (..), throwIO)
import Control.Monad.Cont (runContT)
import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.Function ((&))
import Data.List (isInfixOf, isPrefixOf, tails)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import qualified Data.Text.Lazy as TL
import Data.Time (getCurrentTime)
import Database.Persist (Entity (..), Key, insert, insert_, selectList, (==.))
import Database.Persist.Sql (ConnectionPool, rawExecute, runSqlPool)
import qualified Domain.Central.Responder.Api.Seed as Seed
import qualified Domain.Project.Model as M
import Environment.Db (withPool)
import Environment.Logging (withLogger)
import Network.HTTP.Types
  ( HeaderName
  , Method
  , hContentType
  , methodGet
  , methodPost
  , methodPut
  , renderSimpleQuery
  , statusCode
  )
import Network.HTTP.Types.URI (decodePath)
import Network.Wai
  ( Application
  , defaultRequest
  , pathInfo
  , queryString
  , rawPathInfo
  , rawQueryString
  , requestHeaders
  , requestMethod
  )
import Network.Wai.Test (SRequest (..), SResponse (..), runSession, srequest)
import System.Directory (makeAbsolute)
import Test.Hspec (Expectation, expectationFailure)
import qualified TestContainers.Hspec as TC

{- | The application under test and the pool it runs over. Specs drive
the application through 'httpGet'/'httpPost'/'httpPut' and read back
what it wrote through the pool.
-}
data TestApp = TestApp
  { testApplication :: Application
  , testPool :: ConnectionPool
  }

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
the action ever sees it, builds the real application over it, and
hands the action both. The container is torn down once the action
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

The application is 'App.Server.app', so the routing, the parameter
parsing and the content negotiation are all the real ones. The
middleware pipeline is not: it is composed in @App.Server.main@
around the application rather than inside it, and none of it is what
these tests are about.
-}
withTestApp :: (TestApp -> IO ()) -> IO ()
withTestApp action = do
  req <- pgRequest
  TC.withContainers (TC.run req) $ \container -> do
    let (dbHost, dbPort') = TC.containerAddress container 5432
        cfg = testAppConfig dbHost dbPort'
    runContT (withPool (dbConf cfg)) $ \pool -> do
      seedReferenceData pool
      runContT withLogger $ \lgr ->
        action
          TestApp
            { testApplication = app (Env cfg lgr pool)
            , testPool = pool
            }

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

testAppConfig :: Text -> Int -> AppConfig
testAppConfig dbHost dbPort' =
  AppConfig
    { envName = Local
    , dbConf = testDbConfig dbHost dbPort'
    , webConf = testWebConfig
    }

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

{- | Values the application under test never reads: nothing here binds a
socket, and the index redirect and request-id header are both read by
middleware the tests do not run.
-}
testWebConfig :: WebConfig
testWebConfig =
  WebConfig
    { indexRedirect = "/ui/projects/vw"
    , port = 0
    , requestIdHeader = "x-request-id"
    }

seedReferenceData :: ConnectionPool -> IO ()
seedReferenceData = runSqlPool Seed.seedReferenceData

{- | Clears every table a test might have written to, without touching
the reference data 'seedReferenceData' inserted once at container
startup. Truncating all three together (rather than deleting in
dependency order) sidesteps FK ordering entirely.
-}
truncateTestData :: ConnectionPool -> IO ()
truncateTestData ta =
  flip runSqlPool ta $
    rawExecute
      "TRUNCATE project.dependency, project.node, project.project RESTART IDENTITY CASCADE"
      []

{- | Hspec @beforeWith@-shaped hook: truncate mutable tables before each
test, then hand the same application through unchanged. Truncating
instead of wrapping each test in a rolled-back transaction is
deliberate -- handlers commit their own transaction via 'runSqlPool',
so there's no outer transaction for a test to roll back (see the
proposal's §5).
-}
resetBetweenTests :: TestApp -> IO TestApp
resetBetweenTests ta = truncateTestData (testPool ta) >> pure ta

{- | Minimal fixture every write test needs: a bare 'M.Project' and a
root 'M.Node' attached to it (status @active@, type @project_root@ --
both from 'seedReferenceData').
-}
seedProjectWithRootNode :: TestApp -> IO (Key M.Project, Key M.Node)
seedProjectWithRootNode ta = flip runSqlPool (testPool ta) $ do
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
seedWorkNode :: TestApp -> Key M.Project -> String -> IO (Key M.Node)
seedWorkNode ta projectKey title = flip runSqlPool (testPool ta) $ do
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
seedDependency :: TestApp -> Key M.Node -> Key M.Node -> IO ()
seedDependency ta dependent dependency =
  flip runSqlPool (testPool ta)
    . insert_
    $ M.Dependency
      { M.dependencyNodeId = dependent
      , M.dependencyToNodeId = dependency
      }

-- | @GET@ the given URL, path and query string and all.
httpGet :: TestApp -> Text -> IO SResponse
httpGet ta url = runRequest ta (requestFor methodGet url Nothing)

{- | @POST@ a form-encoded body to the given URL. Build the body with
'formBody' rather than by hand: the browser percent-encodes what it
submits, and a test that doesn't is sending a different request.
-}
httpPost :: TestApp -> Text -> BS.ByteString -> IO SResponse
httpPost ta url body = runRequest ta (requestFor methodPost url (Just body))

-- | @PUT@ a form-encoded body to the given URL.
httpPut :: TestApp -> Text -> BS.ByteString -> IO SResponse
httpPut ta url body = runRequest ta (requestFor methodPut url (Just body))

runRequest :: TestApp -> SRequest -> IO SResponse
runRequest ta sreq = runSession (srequest sreq) (testApplication ta)

{- | Both halves of the URL have to agree: the router matches on
'pathInfo' and every parameter is read off 'queryString', so
splitting one URL with 'decodePath' rules out a request that 404s
for a reason that has nothing to do with what the test is asserting.
-}
requestFor :: Method -> Text -> Maybe BS.ByteString -> SRequest
requestFor method url body =
  SRequest
    { simpleRequest =
        defaultRequest
          { requestMethod = method
          , pathInfo = path
          , queryString = query
          , rawPathInfo = rawPath
          , rawQueryString = rawQuery
          , requestHeaders =
              [(hContentType, "application/x-www-form-urlencoded") | Just _ <- [body]]
          }
    , simpleRequestBody = maybe LBS.empty LBS.fromStrict body
    }
  where
    raw = encodeUtf8 url
    (rawPath, rawQuery) = C8.break (== '?') raw
    (path, query) = decodePath raw

-- | Percent-encode a form the way the browser submits one.
formBody :: [(BS.ByteString, BS.ByteString)] -> BS.ByteString
formBody = renderSimpleQuery False

bodyOf :: SResponse -> String
bodyOf = LC8.unpack . simpleBody

headerOf :: HeaderName -> SResponse -> Maybe BS.ByteString
headerOf name = lookup name . simpleHeaders

statusOf :: SResponse -> Int
statusOf = statusCode . simpleStatus

shouldContainStr :: String -> String -> Expectation
shouldContainStr haystack needle
  | needle `isInfixOf` haystack = pure ()
  | otherwise =
      expectationFailure ("expected the response to contain " <> show needle)

shouldNotContainStr :: String -> String -> Expectation
shouldNotContainStr haystack needle
  | needle `isInfixOf` haystack =
      expectationFailure ("expected the response not to contain " <> show needle)
  | otherwise = pure ()

{- | How many times @needle@ occurs in @haystack@. Presence is not always
the assertion: one element wired up and two left behind reads exactly
like all three to an 'isInfixOf' check.
-}
countStr :: String -> String -> Int
countStr needle = length . filter (needle `isPrefixOf`) . tails

{- | Where @needle@ first occurs in @haystack@, or its length if it does
not occur at all -- which keeps an ordering assertion honest when the
element is missing entirely.
-}
indexOfStr :: String -> String -> Int
indexOfStr needle = length . takeWhile (not . (needle `isPrefixOf`)) . tails
