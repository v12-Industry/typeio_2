module Domain.Project.Responder.Ui.Container where

import Config.Visualization (Visualization (..))
import Database.Persist.Sql (ConnectionPool)
import Domain.Project.Responder.Ui.ProjectCreate.Submit (handleProjectSubmit)
import Domain.Project.Responder.Ui.ProjectCreate.View (handleProjectCreateVw)
import Domain.Project.Responder.Ui.ProjectIndex.List (handleProjectList)
import Domain.Project.Responder.Ui.ProjectIndex.View (handleProjectView)
import Domain.Project.Responder.Ui.ProjectManage.Node (handleGetNodePanel)
import Domain.Project.Responder.Ui.ProjectManage.Node.Description (handlePutDescription)
import Domain.Project.Responder.Ui.ProjectManage.Node.Detail (handleGetNodeDetail)
import Domain.Project.Responder.Ui.ProjectManage.Node.Edit (handleGetNodeEdit)
import Domain.Project.Responder.Ui.ProjectManage.Node.Refresh (handleGetNodeRefresh)
import Domain.Project.Responder.Ui.ProjectManage.Node.Status (handlePutNodeStatus)
import Domain.Project.Responder.Ui.ProjectManage.Node.Title (handlePutTitle)
import Domain.Project.Responder.Ui.ProjectManage.View (handleProjectManageView)
import Domain.Project.Visualization.Common (RenderGraph, handleGraph)
import qualified Domain.Project.Visualization.Layered.Responder as Layered
import qualified Domain.Project.Visualization.Orbital.Responder as Orbital
import qualified Domain.Project.Visualization.Rootless.Responder as Rootless
import Network.Wai
  ( Application
  , Response
  , ResponseReceived
  )

data Container = Container
  { projectIndexVw :: (Response -> IO ResponseReceived) -> IO ResponseReceived
  , projectList :: (Response -> IO ResponseReceived) -> IO ResponseReceived
  , createProjectVw :: (Response -> IO ResponseReceived) -> IO ResponseReceived
  , manageProjectVw :: Application
  , getProjectGraph :: Application
  , getNodeDetail :: Application
  , getNodeEdit :: Application
  , getNodePanel :: Application
  , getNodeRefresh :: Application
  , putNodeDescription :: Application
  , putNodeStatus :: Application
  , putNodeTitle :: Application
  , submitProject :: Application
  }

{- | Which drawing each 'Visualization' is.

The whole of what this module knows about visualizations, and the one
place a new one has to be added — alongside the constructor itself and
'Config.Visualization.defaultVisualization'.

Selection moved from construction time to request time in #223: the
graph endpoint now reads an optional @visualizationMode@ query
parameter, so all three drawings are live in one process and a link can
name the one it wants. Before that this was applied once, at boot, to a
value read from @GRAPH_VISUALIZATION@.

The table is here rather than in "Domain.Project.Visualization.Common"
so that the shared request handling never learns which drawings exist —
it takes this function and applies it. See
@docs/architecture/visualization-switching.md@.
-}
renderFor :: Visualization -> RenderGraph
renderFor Layered = Layered.renderGraph
renderFor Rootless = Rootless.renderGraph
renderFor Orbital = Orbital.renderGraph

defaultContainer :: ConnectionPool -> Container
defaultContainer pl =
  Container
    { projectIndexVw = handleProjectView
    , projectList = handleProjectList pl
    , createProjectVw = handleProjectCreateVw
    , manageProjectVw = handleProjectManageView
    , getProjectGraph = handleGraph renderFor pl
    , getNodeDetail = handleGetNodeDetail pl
    , getNodeEdit = handleGetNodeEdit pl
    , getNodePanel = handleGetNodePanel
    , getNodeRefresh = handleGetNodeRefresh pl
    , putNodeDescription = handlePutDescription pl
    , putNodeStatus = handlePutNodeStatus pl
    , putNodeTitle = handlePutTitle pl
    , submitProject = handleProjectSubmit pl
    }
