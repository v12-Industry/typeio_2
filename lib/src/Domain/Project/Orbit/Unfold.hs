module Domain.Project.Orbit.Unfold
  ( heads
  , unfold
  , discs
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Domain.Project.Orbit.Types
  ( NodeId
  , OrbitEdge (..)
  , OrbitNode (..)
  , OrbitTree (..)
  )

heads :: [OrbitNode] -> [OrbitEdge] -> [NodeId]
heads ns es = [n | n <- S.toAscList present, not (n `S.member` waitedOn)]
  where
    present = S.fromList (map onId ns)
    waitedOn = S.fromList (map oeDependency (liveEdges present es))

unfold :: [OrbitNode] -> [OrbitEdge] -> [OrbitTree]
unfold ns es = numberForest (map (raw S.empty) roots)
  where
    present = S.fromList (map onId ns)
    es' = liveEdges present es

    below :: Map NodeId [NodeId]
    below =
      M.map (S.toAscList . S.fromList) $
        M.fromListWith
          (<>)
          [(oeDependent e, [oeDependency e]) | e <- es']

    hs = heads ns es
    roots = hs <> anchors (S.toAscList present) (reach S.empty hs)

    anchors :: [NodeId] -> Set NodeId -> [NodeId]
    anchors [] _ = []
    anchors (n : rest) seen
      | n `S.member` seen = anchors rest seen
      | otherwise = n : anchors rest (reach seen [n])

    reach :: Set NodeId -> [NodeId] -> Set NodeId
    reach seen [] = seen
    reach seen (n : rest)
      | n `S.member` seen = reach seen rest
      | otherwise = reach (S.insert n seen) (M.findWithDefault [] n below <> rest)

    raw :: Set NodeId -> NodeId -> Raw
    raw path n =
      Raw n [raw path' c | c <- M.findWithDefault [] n below, not (c `S.member` path')]
      where
        path' = S.insert n path

discs :: [OrbitTree] -> [OrbitTree]
discs = concatMap go
  where
    go t = t : concatMap go (otChildren t)

data Raw = Raw NodeId [Raw]

numberForest :: [Raw] -> [OrbitTree]
numberForest = go M.empty
  where
    go _ [] = []
    go counts (r : rest) =
      let (t, counts') = number 0 counts r
       in t : go counts' rest

number :: Int -> Map NodeId Int -> Raw -> (OrbitTree, Map NodeId Int)
number ring counts (Raw n kids) =
  (OrbitTree n replica ring kids', counts'')
  where
    replica = M.findWithDefault 0 n counts
    counts' = M.insert n (replica + 1) counts
    (kids', counts'') = foldl step ([], counts') kids
    step (acc, c) k =
      let (k', c') = number (ring + 1) c k
       in (acc <> [k'], c')

liveEdges :: Set NodeId -> [OrbitEdge] -> [OrbitEdge]
liveEdges present =
  filter
    ( \e ->
        oeDependent e `S.member` present
          && oeDependency e `S.member` present
    )
