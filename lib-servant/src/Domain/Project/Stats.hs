{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Stats
  ( ProjectStats (..)
  , StatusCount (..)
  , completedStatus
  , projectStats
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)

data StatusCount = StatusCount
  { scStatus :: Text
  , scCount :: Int
  }
  deriving (Eq, Show)

data ProjectStats = ProjectStats
  { psTotal :: Int
  , psByStatus :: [StatusCount]
  , psCompletion :: Int
  }
  deriving (Eq, Show)

completedStatus :: Text
completedStatus = "closed"

projectStats :: [Text] -> Map Text Int -> ProjectStats
projectStats vocabulary counts =
  ProjectStats
    { psTotal = total
    , psByStatus = rows
    , psCompletion = completion
    }
  where
    rows =
      [ StatusCount st (Map.findWithDefault 0 st counts)
      | st <- vocabulary
      ]
    total = sum (Map.elems counts)
    done = Map.findWithDefault 0 completedStatus counts
    completion
      | total == 0 = 0
      | otherwise = round (100 * fromIntegral done / fromIntegral total :: Double)
