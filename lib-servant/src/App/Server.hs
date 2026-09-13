{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module App.Server
  ( main
  , app
  , server
  ) where

import App.Api
  ( Api
  , CreateProjectUi
  , CreatedNode (..)
  , Health (..)
  , HxRedirect
  , ManageProjectUi
  , NodeFieldUi
  , NodeUi
  , ProjectApi
  , ProjectsUi
  , api
  )
import App.Env (AppM, Env (..), runDb, withEnv)
import App.Middleware (withMiddleware)
import App.Params ()
import Config.App (AppConfig (..), loadConfig)
import Config.Visualization (Visualization, defaultVisualization)
import Config.Web (WebConfig (..))
import Configuration.Dotenv (defaultConfig, loadFile)
import Control.Exception (SomeException, try)
import Control.Monad.Error.Class (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT, asks, runReaderT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either (EitherT, firstEitherT, hoistMaybe, runEitherT)
import Data.Aeson (encode, object, (.=))
import Data.Int (Int64)
import Data.Maybe (fromMaybe)
import Data.Text (Text, pack, unpack)
import Data.Text.Encoding (decodeUtf8)
import Data.Text.Util (intToText)
import Data.Time (getCurrentTime)
import Database.Persist (Entity (..), entityKey, entityVal, replace)
import Database.Persist.Sql (SqlBackend, fromSqlKey)
import Domain.Central.Responder.Api.Seed (seedReferenceData)
import Domain.Central.Responder.Ui.Empty (templateEmpty)
import qualified Domain.Project.Model as M
import qualified Domain.Project.Responder.Api.Node.Get as NodeGet
import qualified Domain.Project.Responder.Api.Node.Post as NodePost
import qualified Domain.Project.Responder.Api.NodeStatus.Get as NodeStatusGet
import qualified Domain.Project.Responder.Api.NodeType.Get as NodeTypeGet
import qualified Domain.Project.Responder.Api.Project.Get as ProjectGet
import qualified Domain.Project.Responder.Ui.ProjectCreate.Submit as Submit
import qualified Domain.Project.Responder.Ui.ProjectCreate.View as CreateView
import qualified Domain.Project.Responder.Ui.ProjectIndex.List as IndexList
import qualified Domain.Project.Responder.Ui.ProjectIndex.View as IndexView
import qualified Domain.Project.Responder.Ui.ProjectManage.Node as NodePanel
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Description as NodeDescription
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Detail as NodeDetail
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Edit as NodeEdit
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Query as NodeQuery
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Refresh as NodeRefresh
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Status as NodeStatus
import qualified Domain.Project.Responder.Ui.ProjectManage.Node.Title as NodeTitle
import Domain.Project.Responder.Ui.ProjectManage.Node.Validation
  ( nodeInProject
  , validateNodeProjectId
  )
import qualified Domain.Project.Responder.Ui.ProjectManage.View as ManageView
import qualified Domain.Project.Visualization.Common as Viz
import Domain.Project.Visualization.Dispatch (renderFor)
import Domain.System.Responder.Config (ConfigDisplay, configDisplay)
import Lucid (Html, renderBS)
import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)
import Platform.Build (BuildInfo (..), buildInfo)
import Servant
  ( Handler
  , Header
  , Headers
  , NoContent (..)
  , Server
  , ServerError
  , ServerT
  , Union
  , WithStatus (..)
  , addHeader
  , err404
  , err422
  , err500
  , errBody
  , errHeaders
  , hoistServer
  , noHeader
  , respond
  , serve
  , (:<|>) (..)
  )
import Web.FormUrlEncoded (Form)

server :: ServerT Api AppM
server =
  healthz
    :<|> emptyView
    :<|> seedDatabase
    :<|> systemConfig
    :<|> projectApi
    :<|> projectsUi
    :<|> createProjectUi
    :<|> manageProjectUi

projectApi :: ServerT ProjectApi AppM
projectApi =
  getNodes
    :<|> postNode
    :<|> getNodeStatuses
    :<|> getNodeTypes
    :<|> getProjects

getNodes :: AppM [NodeGet.Node]
getNodes = runDb NodeGet.listNodes

getNodeStatuses :: AppM [NodeStatusGet.NodeStatus]
getNodeStatuses = runDb NodeStatusGet.listNodeStatuses

getNodeTypes :: AppM [NodeTypeGet.NodeType]
getNodeTypes = runDb NodeTypeGet.listNodeTypes

getProjects :: AppM [ProjectGet.Project]
getProjects = runDb ProjectGet.listProjects

postNode ::
  Form ->
  AppM (Headers '[Header "Location" Text] CreatedNode)
postNode form = do
  now <- liftIO getCurrentTime
  rslt <- runDb (NodePost.createNode (NodePost.formToPostNodeForm form) now)
  case rslt of
    Left (NodePost.FailValidation es) -> throwError err422 {errBody = errJson es}
    Left NodePost.ProjectNotFound ->
      throwError err404 {errBody = errJson ["Project not found" :: Text]}
    Left NodePost.MissingStatus -> throwError err500 {errBody = serverErr}
    Left NodePost.MissingType -> throwError err500 {errBody = serverErr}
    Right (Entity ky _) ->
      let nid = fromSqlKey ky
       in pure $
            addHeader
              ("/api/project/nodes/" <> intToText nid)
              (CreatedNode nid)
  where
    errJson es = encode (object ["error" .= es])
    serverErr = errJson ["Internal server error" :: Text]

projectsUi :: ServerT ProjectsUi AppM
projectsUi = projectIndexVw :<|> projectList

projectIndexVw :: AppM (Html ())
projectIndexVw = pure IndexView.projectIndexVwTemplate

projectList :: AppM (Html ())
projectList = do
  ps <- runDb IndexList.queryProjectVw
  pure $ case ps of
    [] -> IndexList.templateEmptyProjects
    _ -> IndexList.templateList (map entityVal ps)

createProjectUi :: ServerT CreateProjectUi AppM
createProjectUi = createProjectVw :<|> submitProject

createProjectVw :: AppM (Html ())
createProjectVw = pure (CreateView.projectCreateVwTemplate CreateView.emptyForm mempty)

submitProject :: Form -> AppM HxRedirect
submitProject f = do
  let form = Submit.formToAddProjectForm f
  now <- liftIO getCurrentTime
  rslt <- runDb (Submit.createProject form now)
  pure $ case rslt of
    Right _ -> addHeader (decodeUtf8 (snd Submit.redirectHeader)) mempty
    Left (Submit.FormValidationFail es) ->
      noHeader (CreateView.projectCreateVwTemplate form es)
    Left _ -> noHeader (CreateView.projectCreateVwTemplate form ["Could not create the project"])

manageProjectUi :: ServerT ManageProjectUi AppM
manageProjectUi =
  manageProjectVw
    :<|> projectGraph
    :<|> (nodeUi :<|> nodeFieldUi)

manageProjectVw ::
  Int64 ->
  Maybe Int64 ->
  Maybe Visualization ->
  Maybe Double ->
  Maybe Double ->
  Maybe Double ->
  AppM (Html ())
manageProjectVw pid nid mviz vx vy vk =
  pure $
    ManageView.templateProject
      ManageView.ManageProjectPayload
        { ManageView.payloadNodeId = nid
        , ManageView.payloadProjectId = pid
        , ManageView.payloadVisualization = viz
        , ManageView.payloadView = ManageView.ViewTransform <$> vx <*> vy <*> vk
        , ManageView.payloadViewBase = viewBase pid nid viz
        }
  where
    viz = fromMaybe defaultVisualization mviz

-- Rebuilt from the parameters the route actually parsed rather than from
-- the raw query string, so the base the viewport appends to is canonical
-- whatever the client sent.
viewBase :: Int64 -> Maybe Int64 -> Visualization -> Text
viewBase pid nid viz =
  "/ui/project/vw?projectId="
    <> intToText pid
    <> maybe "" (\n -> "&nodeId=" <> intToText n) nid
    <> "&visualizationMode="
    <> pack (show viz)

projectGraph :: Int64 -> Maybe Visualization -> AppM (Html ())
projectGraph pid mviz = do
  ns <- runDb (Viz.queryNodes pid)
  case ns of
    [] -> throwError err404 {errBody = encode (object ["error" .= noNodes])}
    _ -> do
      ds <- runDb (Viz.queryDependencies (map (fromSqlKey . entityKey) ns))
      pure $ renderFor (fromMaybe defaultVisualization mviz) pid ns ds
  where
    noNodes = "No nodes found for the project" :: Text

nodeUi :: ServerT NodeUi AppM
nodeUi = nodePanel :<|> nodeDetail :<|> nodeEdit :<|> nodeRefresh

nodePanel :: Int64 -> Int64 -> AppM (Html ())
nodePanel pid nid = pure (NodePanel.templateNodePanel nid pid)

nodeDetail :: Int64 -> Int64 -> AppM (Html ())
nodeDetail pid nid =
  renderNode
    pid
    nid
    NodeDetail.templateNodeNotFound
    NodeDetail.templateInvalidParams
    (pure . NodeDetail.templateNodeDetail . entityVal)

nodeEdit :: Int64 -> Int64 -> AppM (Html ())
nodeEdit pid nid =
  renderNode
    pid
    nid
    NodeEdit.templateNodeNotFound
    NodeEdit.templateInvalidParams
    ( \nde -> do
        nsts <- runDb NodeEdit.queryNodeStatuses
        pure (NodeEdit.templateNodeEdit nsts nde)
    )

renderNode ::
  Int64 ->
  Int64 ->
  Html () ->
  ([Text] -> Html ()) ->
  (Entity M.Node -> AppM (Html ())) ->
  AppM (Html ())
renderNode pid nid missing invalid found = do
  mnde <- runDb (NodeQuery.queryNode nid)
  case mnde of
    Nothing -> pure missing
    Just ent -> either (pure . invalid) found (nodeInProject pid ent)

nodeRefresh ::
  Int64 ->
  Int64 ->
  Text ->
  Maybe Int ->
  AppM (Union '[WithStatus 200 (Html ()), WithStatus 204 NoContent])
nodeRefresh pid nid clientTitle mwrap = do
  mnde <- runDb (NodeQuery.queryNode nid)
  case mnde >>= either (const Nothing) Just . nodeInProject pid of
    Nothing -> throwError err404 {errBody = "Node not found"}
    Just nde
      | pack (M.nodeTitle (entityVal nde)) == clientTitle ->
          respond (WithStatus @204 NoContent)
      | otherwise ->
          respond (WithStatus @200 (NodeRefresh.templateRefresh wrapWidth nde))
  where
    wrapWidth = fromMaybe NodeRefresh.defaultWrapWidth mwrap
nodeFieldUi :: ServerT NodeFieldUi AppM
nodeFieldUi = putNodeTitle :<|> putNodeDescription :<|> putNodeStatus

putNodeTitle :: Form -> AppM (Html ())
putNodeTitle form =
  updateNodeField
    NodeTitle.templateNodeNotFound
    NodeTitle.templatePostFail
    NodeTitle.templatePostSuccess
    $ do
      pyld <-
        firstEitherT FieldInvalid
          . NodeTitle.validatePayload
          . NodeTitle.formToPutNodeTitleForm
          $ form
      nde <- nodeForUpdate (NodeTitle.payloadProjectId pyld) (NodeTitle.payloadNodeId pyld)
      lift . replace (entityKey nde) $
        (entityVal nde) {M.nodeTitle = unpack (NodeTitle.payloadTitle pyld)}

putNodeDescription :: Form -> AppM (Html ())
putNodeDescription form =
  updateNodeField
    NodeDescription.templateNodeNotFound
    NodeDescription.templatePutFail
    NodeDescription.templatePutSuccess
    $ do
      pyld <-
        firstEitherT FieldInvalid
          . NodeDescription.validatePayload
          . NodeDescription.formToPutNodeDescriptionForm
          $ form
      nde <-
        nodeForUpdate
          (NodeDescription.payloadProjectId pyld)
          (NodeDescription.payloadNodeId pyld)
      lift . replace (entityKey nde) $
        (entityVal nde) {M.nodeDescription = unpack (NodeDescription.payloadDescription pyld)}

putNodeStatus :: Form -> AppM (Html ())
putNodeStatus form =
  updateNodeField
    NodeStatus.templateNodeNotFound
    NodeStatus.templatePostFail
    NodeStatus.templatePostSuccess
    $ do
      pyld <-
        firstEitherT FieldInvalid
          . NodeStatus.validatePayload
          . NodeStatus.formToPostNodeStatusForm
          $ form
      nde <- nodeForUpdate (NodeStatus.payloadProjectId pyld) (NodeStatus.payloadNodeId pyld)
      sts <-
        lift (NodeStatus.queryStatus (NodeStatus.payloadStatus pyld))
          >>= hoistMaybe (FieldInvalid ["Node status is required"])
      lift . replace (entityKey nde) $
        (entityVal nde) {M.nodeNodeStatusId = entityKey sts}

data FieldUpdateErr
  = FieldInvalid [Text]
  | FieldNodeMissing

nodeForUpdate ::
  Int64 ->
  Int64 ->
  EitherT FieldUpdateErr (ReaderT SqlBackend IO) (Entity M.Node)
nodeForUpdate pid nid =
  lift (NodeQuery.queryNode nid)
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

healthz :: AppM Health
healthz =
  pure
    Health
      { healthStatus = "ok"
      , healthCommit = pack (commit buildInfo)
      }

emptyView :: AppM (Html ())
emptyView = pure templateEmpty

seedDatabase :: AppM Text
seedDatabase = do
  runDb seedReferenceData
  pure "Database seeded successfully"

systemConfig :: AppM ConfigDisplay
systemConfig = asks (configDisplay . envConfig)

hoisted :: Env -> Server Api
hoisted ev = hoistServer api (nt ev) server

nt :: Env -> AppM a -> Handler a
nt ev a = runReaderT a ev

app :: Env -> Application
app = serve api . hoisted

main :: IO ()
main = do
  loadDotEnv
  cfg <- loadConfig
  withEnv cfg $ \ev ->
    withMiddleware ev $ \md ->
      run (port (webConf cfg)) (md (app ev))

loadDotEnv :: IO ()
loadDotEnv = do
  _ <- try (loadFile defaultConfig) :: IO (Either SomeException ())
  return ()
