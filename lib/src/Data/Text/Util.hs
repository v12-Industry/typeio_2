{-# LANGUAGE OverloadedStrings #-}

module Data.Text.Util where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Lazy (toStrict)
import Data.Text.Lazy.Builder (toLazyText)
import Data.Text.Lazy.Builder.Int (decimal)

intToText :: Integral a => a -> Text
intToText = toStrict . toLazyText . decimal

wrapLabel :: Int -> Int -> Text -> [Text]
wrapLabel width maxLines label
  | width <= 0 || maxLines <= 0 = []
  | otherwise = clamp . greedy . concatMap hardSplit . T.words $ label
  where
    hardSplit w
      | T.length w <= width = [w]
      | otherwise = T.chunksOf width w

    greedy = foldl step []
    step [] w = [w]
    step acc w =
      let ln = last acc
       in if T.length ln + 1 + T.length w <= width
            then init acc ++ [ln <> " " <> w]
            else acc ++ [w]

    clamp ls
      | length ls <= maxLines = ls
      | otherwise =
          let kept = take maxLines ls
              lst = last kept
              room = max 0 (width - 1)
           in init kept ++ [T.take room lst <> "…"]
