{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Api.Project.Get where

import Control.Monad.Reader (ReaderT)
import Data.Aeson
  ( ToJSON
  , encode
  , object
  , toJSON
  , (.=)
  )
import Data.Int (Int64)
import Database.Esqueleto.Experimental (from, select, table)
import Database.Persist (Entity (..))
import Database.Persist.Sql (ConnectionPool, SqlBackend, fromSqlKey, runSqlPool)
import qualified Domain.Project.Model as M (Project (..))
import Network.HTTP.Types (status200)
import Network.Wai (Response, ResponseReceived, responseLBS)

newtype Project = Project
  { projectId :: Int64
  }

instance ToJSON Project where
  toJSON (Project pId) =
    object ["projectId" .= pId]

handleGetProjects :: ConnectionPool -> (Response -> IO ResponseReceived) -> IO ResponseReceived
handleGetProjects pl respond = do
  ns <- encode <$> runSqlPool listProjects pl
  respond $ responseLBS status200 [("Content-Type", "application/json")] ns

listProjects :: ReaderT SqlBackend IO [Project]
listProjects = map toSchema <$> query
  where
    query = select $ from $ table @M.Project
    toSchema (Entity k _) =
      Project
        { projectId = fromSqlKey k
        }
