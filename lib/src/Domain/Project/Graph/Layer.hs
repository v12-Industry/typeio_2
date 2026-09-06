module Domain.Project.Graph.Layer
  ( Arc (..)
  , Segment (..)
  , breakCycles
  , assignLayers
  , insertDummies
  ) where

import Data.Foldable (foldl')
import Data.List (sort, sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (mapMaybe)
import Data.Set (Set)
import qualified Data.Set as S
import Domain.Project.Graph.Types
  ( EdgeId
  , EdgeKind (..)
  , LNode (..)
  , LayoutEdge (..)
  , LayoutNode (..)
  , NodeId
  )

data Arc = Arc
  { arcEdge :: EdgeId
  , arcKind :: EdgeKind
  , arcFrom :: NodeId
  , arcTo :: NodeId
  , arcReversed :: Bool
  }
  deriving (Eq, Show)

breakCycles :: [LayoutNode] -> [LayoutEdge] -> [Arc]
breakCycles ns es = map orient es
  where
    backs = backEdges ns es

    orient e
      | leId e `S.member` backs =
          Arc (leId e) (leKind e) (leLower e) (leUpper e) True
      | otherwise =
          Arc (leId e) (leKind e) (leUpper e) (leLower e) False

data Dfs = Dfs
  { dfsSeen :: Set NodeId
  , dfsOnStack :: Set NodeId
  , dfsBack :: Set EdgeId
  }

backEdges :: [LayoutNode] -> [LayoutEdge] -> Set EdgeId
backEdges ns es = dfsBack (foldl' fromRoot start (sort (map lnId ns)))
  where
    start = Dfs S.empty S.empty S.empty

    outgoing =
      M.fromListWith
        (++)
        [(leUpper e, [e]) | e <- es]
    outOf n = sortOn leId (M.findWithDefault [] n outgoing)
    fromRoot st n
      | n `S.member` dfsSeen st = st
      | otherwise = visit st n
    visit st n =
      let entered =
            st
              { dfsSeen = S.insert n (dfsSeen st)
              , dfsOnStack = S.insert n (dfsOnStack st)
              }
          descended = foldl' step entered (outOf n)
       in descended {dfsOnStack = S.delete n (dfsOnStack descended)}
    step st e
      | tgt `S.member` dfsOnStack st =
          st {dfsBack = S.insert (leId e) (dfsBack st)}
      | tgt `S.member` dfsSeen st = st
      | otherwise = visit st tgt
      where
        tgt = leLower e

assignLayers :: [LayoutNode] -> [Arc] -> Map NodeId Int
assignLayers ns arcs = snd (foldl' go (S.empty, M.empty) (sort (map lnId ns)))
  where
    above =
      M.fromListWith
        (++)
        [(arcTo a, [arcFrom a]) | a <- arcs]
    go acc@(active, memo) n
      | n `M.member` memo = acc
      | n `S.member` active = acc
      | otherwise =
          let ps = sort (M.findWithDefault [] n above)
              (active', memo') = foldl' go (S.insert n active, memo) ps
              lvl = case mapMaybe (`M.lookup` memo') ps of
                [] -> 0
                ls -> 1 + maximum ls
           in (S.delete n active', M.insert n lvl memo')

data Segment = Segment
  { segEdge :: EdgeId
  , segKind :: EdgeKind
  , segFrom :: LNode
  , segTo :: LNode
  , segReversed :: Bool
  }
  deriving (Eq, Show)

insertDummies ::
  Map NodeId Int ->
  [Arc] ->
  ([Segment], Map LNode Int, Map EdgeId [LNode])
insertDummies layers arcs =
  ( concatMap segmentsOf arcs
  , M.fromList (realSlots <> dummySlots)
  , M.fromList (map (\a -> (arcEdge a, chainOf a)) arcs)
  )
  where
    layerOf n = M.findWithDefault 0 n layers
    realSlots = [(Real n, l) | (n, l) <- M.toList layers]
    dummySlots =
      [ (d, l)
      | a <- arcs
      , (d, l) <- zip (dummiesOf a) [layerOf (arcFrom a) + 1 ..]
      ]

    dummiesOf a =
      [ Dummy (arcEdge a) l
      | l <- [layerOf (arcFrom a) + 1 .. layerOf (arcTo a) - 1]
      ]

    chainOf a = [Real (arcFrom a)] <> dummiesOf a <> [Real (arcTo a)]

    segmentsOf a =
      [ Segment (arcEdge a) (arcKind a) u v (arcReversed a)
      | (u, v) <- zip chain (drop 1 chain)
      ]
      where
        chain = chainOf a
