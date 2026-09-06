module Domain.Project.Container where

import Database.Persist.Sql (ConnectionPool)
import qualified Domain.Project.Responder.Api.Container as Api
import qualified Domain.Project.Responder.Ui.Container as Ui

data ProjectContainer = ProjectContainer
  { projectApiContainer' :: Api.Container
  , projectUiContainer' :: Ui.Container
  }

{- | Takes only the pool.

It used to take the selected 'Config.Visualization.Visualization' too,
threaded down from 'Config.App.AppConfig' so the UI container could bind
one handler at construction. #223 moved that choice onto the request, so
there is nothing to thread: every drawing is live in one process and the
graph endpoint picks per request.
-}
defaultContainer :: ConnectionPool -> ProjectContainer
defaultContainer pl =
  ProjectContainer
    { projectApiContainer' = Api.defaultContainer pl
    , projectUiContainer' = Ui.defaultContainer pl
    }
