module Domain.Project.Container where

import Database.Persist.Sql (ConnectionPool)
import qualified Domain.Project.Responder.Api.Container as Api
import qualified Domain.Project.Responder.Ui.Container as Ui

data ProjectContainer = ProjectContainer
  { projectApiContainer' :: Api.Container
  , projectUiContainer' :: Ui.Container
  }

defaultContainer :: ConnectionPool -> ProjectContainer
defaultContainer pl =
  ProjectContainer
    { projectApiContainer' = Api.defaultContainer pl
    , projectUiContainer' = Ui.defaultContainer pl
    }
