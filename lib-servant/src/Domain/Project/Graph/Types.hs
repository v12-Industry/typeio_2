{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Graph.Types
  ( NodeId (..)
  , EdgeId (..)
  , NodeKind (..)
  , LNode (..)
  , isDummy
  , LayoutNode (..)
  , LayoutEdge (..)
  , EdgeKind (..)
  , dependsOn
  , contains
  , Point (..)
  , Size (..)
  , Bounds (..)
  , PlacedNode (..)
  , PlacedEdge (..)
  , Diagram (..)
  , LayoutConfig (..)
  , defaultLayoutConfig
  , boundsSize
  ) where

import Data.Int (Int64)
import Data.Text (Text)

newtype NodeId = NodeId Int64
  deriving (Eq, Ord, Show)

newtype EdgeId = EdgeId Int64
  deriving (Eq, Ord, Show)

data NodeKind
  = RootNode
  | WorkNode
  deriving (Eq, Show)

data LayoutNode = LayoutNode
  { lnId :: NodeId
  , lnKind :: NodeKind
  , lnLabel :: Text
  }
  deriving (Eq, Show)

data EdgeKind
  = DependsOn
  | Contains
  deriving (Eq, Show)

data LayoutEdge = LayoutEdge
  { leId :: EdgeId
  , leKind :: EdgeKind
  , leUpper :: NodeId
  , leLower :: NodeId
  }
  deriving (Eq, Show)

dependsOn :: EdgeId -> NodeId -> NodeId -> LayoutEdge
dependsOn i dependency dependent =
  LayoutEdge i DependsOn dependent dependency

contains :: EdgeId -> NodeId -> NodeId -> LayoutEdge
contains i container contained =
  LayoutEdge i Contains container contained

data LNode
  = Real NodeId
  | Dummy EdgeId Int
  deriving (Eq, Ord, Show)

isDummy :: LNode -> Bool
isDummy (Dummy _ _) = True
isDummy (Real _) = False

data Point = Point
  { ptX :: Double
  , ptY :: Double
  }
  deriving (Eq, Show)

data Size = Size
  { szW :: Double
  , szH :: Double
  }
  deriving (Eq, Show)

data Bounds = Bounds
  { bMin :: Point
  , bMax :: Point
  }
  deriving (Eq, Show)

data PlacedNode = PlacedNode
  { pnId :: NodeId
  , pnKind :: NodeKind
  , pnLines :: [Text]
  , pnTopLeft :: Point
  , pnSize :: Size
  }
  deriving (Eq, Show)

data PlacedEdge = PlacedEdge
  { peId :: EdgeId
  , peKind :: EdgeKind
  , pePoints :: [Point]
  , peReversed :: Bool
  , peJumps :: [Point]
  }
  deriving (Eq, Show)

data Diagram = Diagram
  { diagramNodes :: [PlacedNode]
  , diagramEdges :: [PlacedEdge]
  , diagramBounds :: Bounds
  , diagramRootAnchor :: Maybe Point
  }
  deriving (Eq, Show)

data LayoutConfig = LayoutConfig
  { cfgNodeSize :: Size
  , cfgLayerGap :: Double
  , cfgNodeGap :: Double
  , cfgDummyWidth :: Double
  , cfgTrackGap :: Double
  , cfgLabelWidth :: Int
  , cfgLabelLines :: Int
  , cfgMargin :: Double
  , cfgJumpRadius :: Double
  }
  deriving (Eq, Show)

defaultLayoutConfig :: LayoutConfig
defaultLayoutConfig =
  LayoutConfig
    { cfgNodeSize = Size 160 64
    , cfgLayerGap = 90
    , cfgNodeGap = 40
    , cfgDummyWidth = 12
    , cfgTrackGap = 18
    , cfgLabelWidth = 18
    , cfgLabelLines = 3
    , cfgMargin = 48
    , cfgJumpRadius = 4
    }

boundsSize :: Bounds -> Size
boundsSize (Bounds mn mx) =
  Size (ptX mx - ptX mn) (ptY mx - ptY mn)
