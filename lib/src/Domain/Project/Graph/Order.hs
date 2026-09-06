module Domain.Project.Graph.Order
  ( orderRows
  , countCrossings
  ) where

import Data.Foldable (foldl')
import Data.List (sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (mapMaybe)
import Domain.Project.Graph.Layer (Segment (..))
import Domain.Project.Graph.Types (LNode)

data Direction = Downward | Upward

orderRows :: Map Int [LNode] -> [Segment] -> Map Int [LNode]
orderRows rows segments = best
  where
    passes = 4
    (_, best, _) =
      foldl'
        step
        (rows, rows, countCrossings rows segments)
        (concat (replicate passes [Downward, Upward]))

    step (current, bestSoFar, bestCount) dir =
      let next = sweep dir current
          count = countCrossings next segments
       in if count < bestCount
            then (next, next, count)
            else (next, bestSoFar, bestCount)

    above = M.fromListWith (++) [(segTo s, [segFrom s]) | s <- segments]
    below = M.fromListWith (++) [(segFrom s, [segTo s]) | s <- segments]

    sweep dir current = foldl' reorder current (rowsToVisit dir current)
      where
        rowsToVisit Downward rs = drop 1 (M.keys rs)
        rowsToVisit Upward rs = drop 1 (reverse (M.keys rs))

        reorder acc l =
          M.insert l (map thd (sortOn key keyed)) acc
          where
            reference = case dir of
              Downward -> l - 1
              Upward -> l + 1
            positions = positionsIn (M.findWithDefault [] reference acc)
            neighbours n =
              M.findWithDefault [] n $ case dir of
                Downward -> above
                Upward -> below
            keyed =
              [ (medianOf (mapMaybe (`M.lookup` positions) (neighbours n)) i, i, n)
              | (i, n) <- zip [0 :: Int ..] (M.findWithDefault [] l acc)
              ]
            key (m, i, _) = (m, i)
            thd (_, _, n) = n

    medianOf [] fallback = fromIntegral fallback :: Double
    medianOf ps _
      | odd n = fromIntegral (sorted !! mid)
      | otherwise = fromIntegral (sorted !! (mid - 1) + sorted !! mid) / 2
      where
        sorted = sortOn id ps
        n = length ps
        mid = n `div` 2

positionsIn :: [LNode] -> Map LNode Int
positionsIn row = M.fromList (zip row [0 ..])

countCrossings :: Map Int [LNode] -> [Segment] -> Int
countCrossings rows segments =
  sum (map crossingsBelow (M.keys rows))
  where
    positions = M.unions (map positionsIn (M.elems rows))
    layerOf n = M.lookup n rowOf
    rowOf = M.fromList [(n, l) | (l, row) <- M.toList rows, n <- row]
    posOf n = M.findWithDefault 0 n positions

    crossingsBelow l =
      inversions
        [ posOf (segTo s)
        | s <- sortOn (posOf . segFrom) (segmentsFrom l)
        ]

    segmentsFrom l = [s | s <- segments, layerOf (segFrom s) == Just l]

    inversions xs =
      length
        [ ()
        | (i, a) <- zip [0 :: Int ..] xs
        , (j, b) <- zip [0 ..] xs
        , i < j
        , a > b
        ]
