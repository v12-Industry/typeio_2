{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module App.Params
  ( parseSqlKey
  ) where

import Config.Visualization
  ( Visualization
  , parseVisualization
  , visualizationText
  )
import Data.Int (Int64)
import Data.Text (Text)
import Database.Persist.Sql (Key, SqlBackend, ToBackendKey, toSqlKey)
import Web.HttpApiData
  ( FromHttpApiData (..)
  , ToHttpApiData (..)
  )

parseSqlKey :: ToBackendKey SqlBackend a => Text -> Either Text (Key a)
parseSqlKey = fmap toSqlKey . parseUrlPiece @Int64

instance FromHttpApiData Visualization where
  parseUrlPiece raw =
    maybe (Left ("Unknown visualization: " <> raw)) Right (parseVisualization raw)

instance ToHttpApiData Visualization where
  toUrlPiece = visualizationText
