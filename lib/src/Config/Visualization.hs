{-# LANGUAGE OverloadedStrings #-}

module Config.Visualization
  ( Visualization (..)
  , defaultVisualization
  ) where

import Data.Aeson (ToJSON, toJSON)

data Visualization
  = Layered
  | Rootless
  | Orbital
  deriving (Eq, Read, Show)

instance ToJSON Visualization where
  toJSON = toJSON . show

defaultVisualization :: Visualization
defaultVisualization = Orbital
