module Domain.Project.Graph.Containment
  ( containmentEdges
  , containmentTargets
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Domain.Project.Graph.Types
  ( EdgeId (..)
  , EdgeKind (..)
  , LayoutEdge (..)
  , LayoutNode (..)
  , NodeId
  , NodeKind (..)
  , contains
  )

containmentEdges :: [LayoutNode] -> [LayoutEdge] -> [LayoutEdge]
containmentEdges lns les =
  case filter ((== RootNode) . lnKind) lns of
    [] -> []
    (root : _) ->
      [ contains (EdgeId (negate i)) (lnId root) t
      | (i, t) <- zip [1 ..] (containmentTargets root lns les)
      ]

containmentTargets :: LayoutNode -> [LayoutNode] -> [LayoutEdge] -> [NodeId]
containmentTargets root lns les = go work S.empty []
  where
    rootId = lnId root
    work = [lnId n | n <- lns, lnId n /= rootId]

    hasDependent :: Set NodeId
    hasDependent =
      S.fromList
        [ leLower e
        | e <- les
        , leKind e == DependsOn
        ]

    below :: Map NodeId [NodeId]
    below =
      M.fromListWith
        (<>)
        [ (leUpper e, [leLower e])
        | e <- les
        , leKind e == DependsOn
        ]

    heads = [n | n <- work, not (n `S.member` hasDependent)]

    reach :: Set NodeId -> [NodeId] -> Set NodeId
    reach seen [] = seen
    reach seen (n : rest)
      | n `S.member` seen = reach seen rest
      | otherwise = reach (S.insert n seen) (M.findWithDefault [] n below <> rest)

    covered0 = reach S.empty (rootId : heads)

    go [] _ acc = heads <> reverse acc
    go (n : rest) extra acc
      | n `S.member` covered0 = go rest extra acc
      | n `S.member` extra = go rest extra acc
      | otherwise =
          let extra' = reach extra [n]
           in go rest extra' (n : acc)
