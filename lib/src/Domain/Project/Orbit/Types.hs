module Domain.Project.Orbit.Types
  ( NodeId (..)
  , OrbitNode (..)
  , OrbitEdge (..)
  , OrbitTree (..)
  , Point (..)
  , Size (..)
  , Bounds (..)
  , boundsSize
  , Disc (..)
  , Link (..)
  , OrbitDiagram (..)
  , OrbitConfig (..)
  , defaultOrbitConfig
  ) where

import Data.Int (Int64)
import Data.Text (Text)

newtype NodeId = NodeId Int64
  deriving (Eq, Ord, Show)

data OrbitNode = OrbitNode
  { onId :: NodeId
  , onLabel :: Text
  }
  deriving (Eq, Show)

data OrbitEdge = OrbitEdge
  { oeDependent :: NodeId
  , oeDependency :: NodeId
  }
  deriving (Eq, Show)

data OrbitTree = OrbitTree
  { otNode :: NodeId
  , otReplica :: Int
  , otRing :: Int
  , otChildren :: [OrbitTree]
  }
  deriving (Eq, Show)

data Point = Point {ptX :: Double, ptY :: Double}
  deriving (Eq, Show)

data Size = Size {szW :: Double, szH :: Double}
  deriving (Eq, Show)

data Bounds = Bounds {bMin :: Point, bMax :: Point}
  deriving (Eq, Show)

boundsSize :: Bounds -> Size
boundsSize (Bounds (Point x0 y0) (Point x1 y1)) = Size (x1 - x0) (y1 - y0)

data Disc = Disc
  { dNode :: NodeId
  , dReplica :: Int
  , dRing :: Int
  , dAngle :: Double
  , dCentre :: Point
  , dLines :: [Text]
  }
  deriving (Eq, Show)

data Link = Link
  { lFrom :: Point
  , lTo :: Point
  }
  deriving (Eq, Show)

data OrbitDiagram = OrbitDiagram
  { odDiscs :: [Disc]
  , odLinks :: [Link]
  , odBounds :: Bounds
  }
  deriving (Eq, Show)

data OrbitConfig = OrbitConfig
  { cfgDiscRadius :: Double
  , cfgDiscGap :: Double
  , cfgMinRingGap :: Double
  , cfgEyeRadius :: Double
  , cfgLabelWidth :: Int
  , cfgLabelLines :: Int
  , cfgMargin :: Double
  }
  deriving (Eq, Show)

defaultOrbitConfig :: OrbitConfig
defaultOrbitConfig =
  OrbitConfig
    { cfgDiscRadius = 45
    , cfgDiscGap = 24
    , cfgMinRingGap = 55
    , cfgEyeRadius = 130
    , cfgLabelWidth = 12
    , cfgLabelLines = 3
    , cfgMargin = 60
    }
