module Domain.Project.Visualization.Rootless.Responder
  ( renderGraph
  , buildGraph
  ) where

import qualified Data.Set as S
import Domain.Project.Graph.Types
  ( LayoutEdge (..)
  , LayoutNode (..)
  , NodeKind (..)
  )
import Domain.Project.Visualization.Common
  ( BuildGraph
  , RenderGraph
  , nodeStatuses
  , serverGraph
  , templateServerGraph
  , toLayoutEdge
  , toLayoutNode
  )

renderGraph :: RenderGraph
renderGraph pid ns ds = templateServerGraph . buildGraph pid ns $ ds

buildGraph :: BuildGraph
buildGraph pid ns ds = serverGraph pid (nodeStatuses ns) work edges
  where
    work = filter ((/= RootNode) . lnKind) . map toLayoutNode $ ns
    drawn = S.fromList . map lnId $ work
    edges =
      [ e
      | e <- map toLayoutEdge ds
      , leUpper e `S.member` drawn
      , leLower e `S.member` drawn
      ]
