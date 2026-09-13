{-# LANGUAGE OverloadedStrings #-}

module Config.Visualization
  ( Visualization (..)
  , VisualizationChoice (..)
  , chosenVisualization
  , defaultVisualization
  , parseVisualization
  , resolveVisualization
  , visualizationText
  ) where

import Data.Aeson (ToJSON, toJSON)
import Data.Text (Text, unpack)
import qualified Data.Text as T
import Text.Read (readMaybe)

data Visualization
  = Rootless
  | Orbital
  deriving (Bounded, Enum, Eq, Read, Show)

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

visualizationText :: Visualization -> Text
visualizationText Rootless = "Rootless"
visualizationText Orbital = "Orbital"

parseVisualization :: Text -> Maybe Visualization
parseVisualization raw =
  lookup
    (T.toLower raw)
    [(T.toLower (visualizationText v), v) | v <- [minBound .. maxBound]]
