{- | The orbital dependency-weighted visualization: the work drawn
radially, with a shared dependency replicated into every work stream
that waits on it.

The drawing and the reasoning behind it are in
@docs/architecture/orbital-dependency-weighted-graph.md@ (#229). In one
paragraph: the dependency graph is unfolded into a forest of trees, one
per /head/ — a node nothing is waiting on — and each tree is drawn
radially outward from an empty centre, ring by dependency depth. A node
with several dependents cannot belong to one tree, so it is drawn once
in each, with its own dependencies replicated along with it. Every
drawn disc then has exactly one dependent and every stream owns a
disjoint wedge, so the drawing contains __no crossing edges at all__ —
structurally absent rather than heuristically minimised.

__This module imports nothing from "Domain.Project.Graph".__ That tree
is the layered layout engine, and this visualization is not layered: it
brings its own geometry in "Domain.Project.Orbit". That is the case
@docs/architecture/visualization-switching.md@'s isolation rule exists
for, and #233 and #242 are what made it actually reachable — the seam
returns @Html ()@ rather than a layered @Diagram@, and the viewport
shell is shared vocabulary rather than part of the layered template.
-}
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
import Domain.Project.Visualization.Orbital.View (templateOrbit)
import Network.Wai (Application)

handleProjectGraph :: ConnectionPool -> Application
handleProjectGraph = handleGraphWith renderGraph

{- | Lay the project out with the orbital geometry and render it.

Neither half is shared with the layered visualizations: 'orbit' is this
visualization's own engine and 'templateOrbit' its own document. What
/is/ shared is everything either side of the seam — parsing the
request, querying the project, the error responses, and the viewport
frame inside 'templateOrbit'.
-}
renderGraph :: RenderGraph
renderGraph pid ns ds =
  templateOrbit pid defaultOrbitConfig (labelsOf ns) (buildOrbit ns ds)

{- | The untruncated titles, which 'Disc' deliberately does not carry —
it holds the label already wrapped to the circle. The per-node refresh
hook needs the original to tell the endpoint what it currently shows.
-}
labelsOf :: [Entity M.Node] -> Map NodeId Text
labelsOf ns = Map.fromList [(onId n, onLabel n) | n <- map toOrbitNode ns]

{- | The project's rows as an orbital drawing.

Two decisions, both inherited from the rootless visualization for the
same reasons (#215):

* __The project root is not drawn.__ Not depicting membership is this
  visualization's premise as much as it is @Rootless@'s — every node
  would otherwise be dragged into a single stream headed by the root,
  which is exactly the convergence the drawing exists to avoid.
* __An edge with an end that is not drawn goes with it.__ A
  @project.dependency@ row pointing at the root — the
  pre-migration-000009 way of recording membership, and still possible
  for any row recorded by hand — would otherwise survive into layout
  naming a node that is not there. 'orbit' is total and would not fail;
  it would draw a link into empty space. So an edge is kept only when
  __both__ ends are still in the drawing.
-}
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

{- | @project.dependency@ stores @node_id@ /depends on/ @to_node_id@
(see @docs\/development\/backend\/database-schema.md@), so @node_id@ is
the dependent — the end drawn nearer the eye, carrying the arrowhead —
and @to_node_id@ is the dependency.

Easy to get backwards from the column names alone, which is why
'OrbitEdge' names its fields for the relationship rather than for
positions.
-}
toOrbitEdge :: Entity M.Dependency -> OrbitEdge
toOrbitEdge (Entity _ e) =
  OrbitEdge
    { oeDependent = NodeId (fromSqlKey (M.dependencyNodeId e))
    , oeDependency = NodeId (fromSqlKey (M.dependencyToNodeId e))
    }
