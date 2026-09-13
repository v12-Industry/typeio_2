{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Api.NodeType.Get where

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
import qualified Domain.Project.Model as M (NodeType (..), unNodeTypeKey)

newtype NodeType = NodeType
  { nodeTypeId :: String
  }

instance ToJSON NodeType where
  toJSON (NodeType ntId) =
    object ["nodeTypeId" .= ntId]

listNodeTypes :: ReaderT SqlBackend IO [NodeType]
listNodeTypes = map toSchema <$> query
  where
    query = select $ from $ table @M.NodeType
    toSchema (Entity k _) =
      NodeType
        { nodeTypeId = M.unNodeTypeKey k
        }

handler :: AppM [NodeType]
handler = runDb listNodeTypes
