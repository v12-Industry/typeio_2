module Domain.Project.Visualization.Dispatch
  ( renderFor
  ) where

import Config.Visualization (Visualization (..))
import Domain.Project.Visualization.Common (RenderGraph)
import qualified Domain.Project.Visualization.Orbital.Responder as Orbital
import qualified Domain.Project.Visualization.Rootless.Responder as Rootless

renderFor :: Visualization -> RenderGraph
renderFor Rootless = Rootless.renderGraph
renderFor Orbital = Orbital.renderGraph
