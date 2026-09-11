module Domain.Project.Visualization.Orbital.Responder
  ( handleProjectGraph
  , renderGraph
  , buildOrbit
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as S
import Data.Text (Text, pack)
import Database.Persist (Entity (..))
import Database.Persist.Sql (ConnectionPool, fromSqlKey)
import qualified Domain.Project.Model as M
import Domain.Project.Orbit.Layout (orbit)
import Domain.Project.Orbit.Types
  ( NodeId (..)
  , OrbitDiagram
  , OrbitEdge (..)
  , OrbitNode (..)
  , defaultOrbitConfig
  )
import Domain.Project.Visualization.Common
  ( RenderGraph
  , handleGraphWith
  )
import Domain.Project.Visualization.Orbital.View
  ( DiscFacts (..)
  , templateOrbit
  )
import Network.Wai (Application)

handleProjectGraph :: ConnectionPool -> Application
handleProjectGraph = handleGraphWith renderGraph

renderGraph :: RenderGraph
renderGraph pid ns ds =
  templateOrbit pid defaultOrbitConfig (factsOf ns) (buildOrbit ns ds)

factsOf :: [Entity M.Node] -> DiscFacts
factsOf ns =
  DiscFacts
    { dfLabels = labelsOf ns
    , dfStatuses = statusesOf ns
    }

labelsOf :: [Entity M.Node] -> Map NodeId Text
labelsOf ns = Map.fromList [(onId n, onLabel n) | n <- map toOrbitNode ns]

statusesOf :: [Entity M.Node] -> Map NodeId Text
statusesOf ns =
  Map.fromList
    [ (NodeId (fromSqlKey k), pack (M.unNodeStatusKey (M.nodeNodeStatusId e)))
    | Entity k e <- ns
    ]

buildOrbit :: [Entity M.Node] -> [Entity M.Dependency] -> OrbitDiagram
buildOrbit ns ds = orbit defaultOrbitConfig work edges
  where
    work = [toOrbitNode n | n <- ns, not (isRoot n)]
    drawn = S.fromList (map onId work)
    edges =
      [ e
      | e <- map toOrbitEdge ds
      , oeDependent e `S.member` drawn
      , oeDependency e `S.member` drawn
      ]

isRoot :: Entity M.Node -> Bool
isRoot (Entity _ e) = M.unNodeTypeKey (M.nodeNodeTypeId e) == "project_root"

toOrbitNode :: Entity M.Node -> OrbitNode
toOrbitNode (Entity k e) =
  OrbitNode
    { onId = NodeId (fromSqlKey k)
    , onLabel = pack (M.nodeTitle e)
    }

toOrbitEdge :: Entity M.Dependency -> OrbitEdge
toOrbitEdge (Entity _ e) =
  OrbitEdge
    { oeDependent = NodeId (fromSqlKey (M.dependencyNodeId e))
    , oeDependency = NodeId (fromSqlKey (M.dependencyToNodeId e))
    }
