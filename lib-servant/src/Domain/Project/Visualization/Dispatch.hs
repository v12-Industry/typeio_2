{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Visualization.Dispatch
  ( handler
  , renderFor
  ) where

import App.Env (AppM, runDb)
import Config.Visualization (Visualization (..), defaultVisualization)
import Control.Monad.Error.Class (throwError)
import Data.Aeson (encode, object, (.=))
import Data.Int (Int64)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Database.Persist (entityKey)
import Database.Persist.Sql (fromSqlKey)
import Domain.Project.Visualization.Common (RenderGraph)
import qualified Domain.Project.Visualization.Common as Viz
import qualified Domain.Project.Visualization.Orbital.Responder as Orbital
import qualified Domain.Project.Visualization.Rootless.Responder as Rootless
import Lucid (Html)
import Servant (err404, errBody)

renderFor :: Visualization -> RenderGraph
renderFor Rootless = Rootless.renderGraph
renderFor Orbital = Orbital.renderGraph

handler :: Int64 -> Maybe Visualization -> AppM (Html ())
handler pid mviz = do
  ns <- runDb (Viz.queryNodes pid)
  case ns of
    [] -> throwError err404 {errBody = encode (object ["error" .= noNodes])}
    _ -> do
      ds <- runDb (Viz.queryDependencies (map (fromSqlKey . entityKey) ns))
      pure $ renderFor (fromMaybe defaultVisualization mviz) pid ns ds
  where
    noNodes = "No nodes found for the project" :: Text
