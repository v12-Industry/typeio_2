{-# LANGUAGE ScopedTypeVariables #-}

module Domain.Project.Graph.Coord
  ( assignX
  , componentsOf
  , packComponents
  ) where

import Data.Foldable (foldl')
import Data.List (sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (mapMaybe)
import Data.Ord (Down (..))
import Data.Set (Set)
import qualified Data.Set as S
import Domain.Project.Graph.Layer (Segment (..))
import Domain.Project.Graph.Types (LNode, isDummy)

assignX ::
  (LNode -> Double) ->
  Double ->
  Map Int [LNode] ->
  [Segment] ->
  Map LNode Double
assignX widthOf gap rows segments =
  packComponents widthOf gap (componentsOf rows segments) $
    foldl' pass initial (concat (replicate passes [Downward, Upward]))
  where
    passes = 4

    sepOf a b = (widthOf a + widthOf b) / 2 + gap

    initial =
      M.fromList
        [ (n, x)
        | row <- M.elems rows
        , (n, x) <- zip row (scanl (+) 0 (zipWith sepOf row (drop 1 row)))
        ]

    above = M.fromListWith (++) [(segTo s, [segFrom s]) | s <- segments]
    below = M.fromListWith (++) [(segFrom s, [segTo s]) | s <- segments]

    referenceOf Downward = above
    referenceOf Upward = below

    rowOrder Downward = M.toAscList rows
    rowOrder Upward = M.toDescList rows

    pass xs dir = foldl' (placeRow dir) xs (map snd (rowOrder dir))

    placeRow dir xs row = foldl' (placeNode dir row) xs (byPriority dir row)

    byPriority dir row =
      sortOn (\n -> (Down (isDummy n), Down (length (neighboursOf dir n)), n)) row

    neighboursOf dir n = M.findWithDefault [] n (referenceOf dir)

    placeNode dir row xs n =
      case medianOf (mapMaybe (`M.lookup` xs) (neighboursOf dir n)) of
        Nothing -> xs
        Just target -> shiftTo sepOf row (priorityIn dir row) xs n target

    priorityIn dir row =
      M.fromList [(n, (isDummy n, length (neighboursOf dir n))) | n <- row]

componentsOf :: Map Int [LNode] -> [Segment] -> [[LNode]]
componentsOf rows segments = go (concat (M.elems rows)) S.empty
  where
    adjacent =
      M.fromListWith
        (<>)
        (concat [[(segFrom s, [segTo s]), (segTo s, [segFrom s])] | s <- segments])

    go [] _ = []
    go (n : ns) seen
      | n `S.member` seen = go ns seen
      | otherwise =
          let found = reach S.empty [n]
           in S.toAscList found : go ns (seen <> found)

    reach :: Set LNode -> [LNode] -> Set LNode
    reach seen [] = seen
    reach seen (m : ms)
      | m `S.member` seen = reach seen ms
      | otherwise =
          reach (S.insert m seen) (M.findWithDefault [] m adjacent <> ms)

packComponents ::
  (LNode -> Double) ->
  Double ->
  [[LNode]] ->
  Map LNode Double ->
  Map LNode Double
packComponents widthOf gap comps xs
  | length comps < 2 = xs
  | otherwise = snd (foldl' place (Nothing, xs) ordered)
  where
    xAt n = M.findWithDefault 0 n xs
    extent c =
      ( minimum [xAt n - widthOf n / 2 | n <- c]
      , maximum [xAt n + widthOf n / 2 | n <- c]
      )

    ordered = sortOn (\c -> (fst (extent c), c)) comps

    place (prevRight, acc) c =
      ( Just (right + shift)
      , foldl' (\m n -> M.adjust (+ shift) n m) acc c
      )
      where
        (left, right) = extent c
        shift = case prevRight of
          Nothing -> 0
          Just pr -> max 0 (pr + gap - left)

data Direction = Downward | Upward

medianOf :: [Double] -> Maybe Double
medianOf [] = Nothing
medianOf vs
  | odd n = Just (sorted !! mid)
  | otherwise = Just ((sorted !! (mid - 1) + sorted !! mid) / 2)
  where
    sorted = sortOn id vs
    n = length vs
    mid = n `div` 2

shiftTo ::
  (LNode -> LNode -> Double) ->
  [LNode] ->
  Map LNode (Bool, Int) ->
  Map LNode Double ->
  LNode ->
  Double ->
  Map LNode Double
shiftTo sepOf row priority xs n target
  | target > current = move 1 (drop (idx + 1) row)
  | target < current = move (-1) (reverse (take idx row))
  | otherwise = xs
  where
    idx = length (takeWhile (/= n) row)
    current = xAt n
    xAt m = M.findWithDefault 0 m xs
    prio m = M.findWithDefault (False, 0) m priority

    move sign neighbours =
      foldl' shove (M.insert n placed xs) (zip offsets movable)
      where
        movable = takeWhile (\m -> prio m < prio n) neighbours

        offsets = drop 1 (scanl (+) 0 (zipWith sepOf (n : movable) movable))
        cap = case drop (length movable) neighbours of
          [] -> target
          (b : _) ->
            let toBlocker =
                  sum (zipWith sepOf (n : movable) (movable <> [b]))
             in xAt b - sign * toBlocker
        placed
          | sign > 0 = min target cap
          | otherwise = max target cap
        shove acc (off, m) =
          let wanted = placed + sign * off
           in M.insert m (outward wanted (M.findWithDefault 0 m acc)) acc
        outward wanted keep
          | sign > 0 = max wanted keep
          | otherwise = min wanted keep
