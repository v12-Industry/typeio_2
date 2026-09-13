{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Api.NodeType.Get where

import Control.Monad.Reader (ReaderT)
import Data.Aeson
  ( ToJSON
  , encode
  , object
  , toJSON
  , (.=)
  )
import Database.Esqueleto.Experimental (from, select, table)
import Database.Persist (Entity (..))
import Database.Persist.Sql (ConnectionPool, SqlBackend, runSqlPool)
import qualified Domain.Project.Model as M (NodeType (..), unNodeTypeKey)
import Network.HTTP.Types (status200)
import Network.Wai (Response, ResponseReceived, responseLBS)

newtype NodeType = NodeType
  { nodeTypeId :: String
  }

instance ToJSON NodeType where
  toJSON (NodeType ntId) =
    object ["nodeTypeId" .= ntId]

handleGetNodeTypes :: ConnectionPool -> (Response -> IO ResponseReceived) -> IO ResponseReceived
handleGetNodeTypes pl respond = do
  ns <- encode <$> runSqlPool listNodeTypes pl
  respond $ responseLBS status200 [("Content-Type", "application/json")] ns

listNodeTypes :: ReaderT SqlBackend IO [NodeType]
listNodeTypes = map toSchema <$> query
  where
    query = select $ from $ table @M.NodeType
    toSchema (Entity k _) =
      NodeType
        { nodeTypeId = M.unNodeTypeKey k
        }
