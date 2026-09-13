module Domain.Project.Responder.Ui.Container where

import Database.Persist.Sql (ConnectionPool)
import Domain.Project.Responder.Ui.ProjectCreate.Submit (handleProjectSubmit)
import Domain.Project.Responder.Ui.ProjectCreate.View (handleProjectCreateVw)
import Domain.Project.Responder.Ui.ProjectIndex.List (handleProjectList)
import Domain.Project.Responder.Ui.ProjectIndex.View (handleProjectView)
import Domain.Project.Responder.Ui.ProjectManage.Node (handleGetNodePanel)
import Domain.Project.Responder.Ui.ProjectManage.Node.Create (handleGetAddWork, handlePostWork)
import Domain.Project.Responder.Ui.ProjectManage.Node.Description (handlePutDescription)
import Domain.Project.Responder.Ui.ProjectManage.Node.Detail (handleGetNodeDetail)
import Domain.Project.Responder.Ui.ProjectManage.Node.Edit (handleGetNodeEdit)
import Domain.Project.Responder.Ui.ProjectManage.Node.Refresh (handleGetNodeRefresh)
import Domain.Project.Responder.Ui.ProjectManage.Node.Status (handlePutNodeStatus)
import Domain.Project.Responder.Ui.ProjectManage.Node.Title (handlePutTitle)
import Domain.Project.Responder.Ui.ProjectManage.Stats (handleGetProjectStats)
import Domain.Project.Responder.Ui.ProjectManage.View (handleProjectManageView)
import Domain.Project.Visualization.Common (handleGraph)
import Domain.Project.Visualization.Dispatch (renderFor)
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
  , getAddWork :: Application
  , getNodeDetail :: Application
  , getNodeEdit :: Application
  , getNodePanel :: Application
  , getNodeRefresh :: Application
  , getProjectStats :: Application
  , postWork :: Application
  , putNodeDescription :: Application
  , putNodeStatus :: Application
  , putNodeTitle :: Application
  , submitProject :: Application
  }

defaultContainer :: ConnectionPool -> Container
defaultContainer pl =
  Container
    { projectIndexVw = handleProjectView
    , projectList = handleProjectList pl
    , createProjectVw = handleProjectCreateVw
    , manageProjectVw = handleProjectManageView
    , getProjectGraph = handleGraph renderFor pl
    , getAddWork = handleGetAddWork
    , getNodeDetail = handleGetNodeDetail pl
    , getNodeEdit = handleGetNodeEdit pl
    , getNodePanel = handleGetNodePanel
    , getNodeRefresh = handleGetNodeRefresh pl
    , getProjectStats = handleGetProjectStats pl
    , postWork = handlePostWork pl
    , putNodeDescription = handlePutDescription pl
    , putNodeStatus = handlePutNodeStatus pl
    , putNodeTitle = handlePutTitle pl
    , submitProject = handleProjectSubmit pl
    }
