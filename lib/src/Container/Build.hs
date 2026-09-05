module Container.Build where

import Container.Root (RootContainer (..))
import qualified Domain.Central.Container as CentralContainer
import qualified Domain.Project.Container as ProjectContainer
import qualified Domain.System.Container as SystemContainer
import Environment.Env (Env (..))

withRootContainer :: Env -> (RootContainer -> IO a) -> IO a
withRootContainer ev k =
  k
    RootContainer
      { appConfig = appConf ev
      , central = CentralContainer.defaultContainer pl
      , project = ProjectContainer.defaultContainer pl
      , system = SystemContainer.defaultContainer (appConf ev) lg
      }
  where
    lg = logger ev
    pl = pool ev
