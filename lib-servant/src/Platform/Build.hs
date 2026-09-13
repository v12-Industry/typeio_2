{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Platform.Build
  ( BuildInfo (..)
  , buildInfo
  , unknownCommit
  ) where

import Data.Aeson (ToJSON, object, toJSON, (.=))
import Development.GitRev (gitHash)

newtype BuildInfo = BuildInfo
  { commit :: String
  }
  deriving (Eq, Read, Show)

instance ToJSON BuildInfo where
  toJSON bi = object ["commit" .= commit bi]

unknownCommit :: String
unknownCommit = "UNKNOWN"

buildInfo :: BuildInfo
buildInfo = BuildInfo {commit = $(gitHash)}
