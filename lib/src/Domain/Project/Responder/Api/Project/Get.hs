{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Api.Project.Get where

import App.Env (AppM, runDb)
import Control.Monad.Reader (ReaderT)
import Data.Aeson
  ( ToJSON
  , object
  , toJSON
  , (.=)
  )
import Data.Int (Int64)
import Database.Esqueleto.Experimental (from, select, table)
import Database.Persist (Entity (..))
import Database.Persist.Sql (SqlBackend, fromSqlKey)
import qualified Domain.Project.Model as M (Project (..))

newtype Project = Project
  { projectId :: Int64
  }

instance ToJSON Project where
  toJSON (Project pId) =
    object ["projectId" .= pId]

listProjects :: ReaderT SqlBackend IO [Project]
listProjects = map toSchema <$> query
  where
    query = select $ from $ table @M.Project
    toSchema (Entity k _) =
      Project
        { projectId = fromSqlKey k
        }

handler :: AppM [Project]
handler = runDb listProjects
