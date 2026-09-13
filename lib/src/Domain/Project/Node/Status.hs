{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Node.Status
  ( NodeStatus (..)
  , nodeStatusFromKey
  , nodeStatusClass
  ) where

import Data.Text (Text)
import qualified Data.Text as T

data NodeStatus
  = StatusOpen
  | StatusActive
  | StatusClosed
  | StatusRejected
  deriving (Eq, Ord, Show, Enum, Bounded)

nodeStatusFromKey :: Text -> Maybe NodeStatus
nodeStatusFromKey key =
  case T.toLower (T.strip key) of
    "open" -> Just StatusOpen
    "active" -> Just StatusActive
    "closed" -> Just StatusClosed
    "rejected" -> Just StatusRejected
    _ -> Nothing

nodeStatusClass :: NodeStatus -> Text
nodeStatusClass StatusOpen = "status-open"
nodeStatusClass StatusActive = "status-active"
nodeStatusClass StatusClosed = "status-closed"
nodeStatusClass StatusRejected = "status-rejected"
