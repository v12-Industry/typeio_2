{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Api.NodeStatus.Get where

import App.Env (AppM, runDb)
import Control.Monad.Reader (ReaderT)
import Data.Aeson
  ( ToJSON
  , object
  , toJSON
  , (.=)
  )
import Database.Esqueleto.Experimental (from, select, table)
import Database.Persist (Entity (..))
import Database.Persist.Sql (SqlBackend)
import qualified Domain.Project.Model as M (NodeStatus (..), unNodeStatusKey)

newtype NodeStatus = NodeStatus
  { nodeStatusId :: String
  }

instance ToJSON NodeStatus where
  toJSON (NodeStatus ntId) =
    object ["nodeStatusId" .= ntId]

listNodeStatuses :: ReaderT SqlBackend IO [NodeStatus]
listNodeStatuses = map toSchema <$> query
  where
    query = select $ from $ table @M.NodeStatus
    toSchema (Entity k _) =
      NodeStatus
        { nodeStatusId = M.unNodeStatusKey k
        }

handler :: AppM [NodeStatus]
handler = runDb listNodeStatuses
