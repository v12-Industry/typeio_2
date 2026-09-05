{- | The rootless visualization: the work, without the project node.

Selected by @?visualizationMode=Rootless@. The project root is left out
of the drawing entirely and no containment edges are derived, so nothing
forces the work to converge on a single box.

Why (#215): the root is free on a project that is one chain, and it is
the dominant source of mess on anything with parallel workstreams.
Measured with this same engine on synthetic fixtures, dropping it took
four independent workstreams from 8 bends and 2 crossings to __zero of
each__ — graphs that contain no crossings inherently, drawn with none.
Six parallel chains went from 6 crossings to 0. The project's own row
stays in the database and still names the project in the index; it just
isn't a node in the picture.
-}
module Domain.Project.Visualization.Rootless.Responder
  ( handleProjectGraph
  , renderGraph
  , buildGraph
  ) where

import qualified Data.Set as S
import Database.Persist.Sql (ConnectionPool)
import Domain.Project.Graph.Types
  ( LayoutEdge (..)
  , LayoutNode (..)
  , NodeKind (..)
  )
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

{- | The same shared layered engine and SVG vocabulary the layered
visualization uses — this one differs only in what it hands them, which
is 'buildGraph' below.
-}
renderGraph :: RenderGraph
renderGraph pid ns ds = templateServerGraph (buildGraph pid ns ds)

{- | The work nodes only, and only the dependencies between them.

Dropping the root means dropping the edges that referred to it, and that
is not optional. A @project.dependency@ row pointing at the root — the
pre-migration-000009 way of recording membership, and still possible for
any row someone records by hand — would otherwise survive into layout
referring to a node that is no longer there. 'layout' is total and would
not fail; it would place the missing end at the origin and draw a stray
arrow into empty space. So edges are kept only when __both__ ends are
still in the drawing.

No containment edges are derived here at all: containment is how the
layered visualization depicts membership, and not depicting it is this
visualization's entire premise.
-}
buildGraph :: BuildGraph
buildGraph pid ns ds = serverGraph pid work edges
  where
    work = filter ((/= RootNode) . lnKind) (map toLayoutNode ns)
    drawn = S.fromList (map lnId work)
    edges =
      [ e
      | e <- map toLayoutEdge ds
      , leUpper e `S.member` drawn
      , leLower e `S.member` drawn
      ]
