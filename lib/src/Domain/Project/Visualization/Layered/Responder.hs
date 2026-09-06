module Domain.Project.Visualization.Layered.Responder
  ( handleProjectGraph
  , renderGraph
  , buildGraph
  ) where

import Database.Persist.Sql (ConnectionPool)
import Domain.Project.Graph.Containment (containmentEdges)
import Domain.Project.Visualization.Common
  ( BuildGraph
  , RenderGraph
  , handleGraphWith
  , serverGraph
  , templateServerGraph
  , toLayoutEdge
  , toLayoutNode
  )
import Network.Wai (Application)

handleProjectGraph :: ConnectionPool -> Application
handleProjectGraph = handleGraphWith renderGraph

renderGraph :: RenderGraph
renderGraph pid ns ds = templateServerGraph (buildGraph pid ns ds)

buildGraph :: BuildGraph
buildGraph pid ns ds = serverGraph pid lns les
  where
    lns = map toLayoutNode ns
    deps = map toLayoutEdge ds
    les = containmentEdges lns deps <> deps
