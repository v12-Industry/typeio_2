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

renderGraph :: RenderGraph
renderGraph pid ns ds = templateServerGraph (buildGraph pid ns ds)

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
