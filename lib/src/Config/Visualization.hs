{-# LANGUAGE OverloadedStrings #-}

module Config.Visualization
  ( Visualization (..)
  , VisualizationChoice (..)
  , chosenVisualization
  , defaultVisualization
  , resolveVisualization
  ) where

import Data.Aeson (ToJSON, toJSON)
import Data.Text (Text, unpack)
import Text.Read (readMaybe)

data Visualization
  = Layered
  | Rootless
  | Orbital
  deriving (Eq, Read, Show)

instance ToJSON Visualization where
  toJSON = toJSON . show

defaultVisualization :: Visualization
defaultVisualization = Orbital

data VisualizationChoice
  = AsRequested Visualization
  | FellBack Visualization
  deriving (Eq, Show)

chosenVisualization :: VisualizationChoice -> Visualization
chosenVisualization (AsRequested v) = v
chosenVisualization (FellBack v) = v

resolveVisualization :: Maybe Text -> VisualizationChoice
resolveVisualization Nothing = AsRequested defaultVisualization
resolveVisualization (Just raw) =
  maybe (FellBack defaultVisualization) AsRequested (readMaybe (unpack raw))
