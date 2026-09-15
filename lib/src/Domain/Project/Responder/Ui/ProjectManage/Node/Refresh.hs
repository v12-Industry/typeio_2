{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Refresh where

import Common.Web.Attributes
import Common.Web.Elements
import Data.Maybe (fromMaybe)
import Domain.Project.Graph.Types (LayoutConfig (..), defaultLayoutConfig)
import Domain.Project.Responder.Ui.ProjectManage.Node.Query
import Domain.Project.Responder.Ui.ProjectManage.Node.Validation
import Domain.Project.Visualization.Common (nodeContents, toGraphNode)
import Lucid

import qualified Domain.Project.Model as M

import App.Env (AppM, runDb)
import Control.Monad.Error.Class (throwError)
import Data.Int (Int64)
import Data.Text (Text, pack)
import Data.Text.Util (intToText)
import Database.Esqueleto.Experimental
import Servant (NoContent (..), Union, WithStatus (..), err404, errBody, respond)

defaultWrapWidth :: Int
defaultWrapWidth = cfgLabelWidth defaultLayoutConfig

templateRefresh :: Int -> Entity M.Node -> Html ()
templateRefresh wrapWidth (Entity k e) = do
  nodeContents wrapWidth . toGraphNode . Entity k $ e
  g_
    [ class_ "hidden"
    , h_ $
        "on load add .flash to "
          <> nsel
          <> " then wait 500ms"
          <> " then remove .flash from "
          <> nsel
          <> " then remove me"
    ]
    empty
  where
    empty = mempty :: Html ()

    nsel =
      "<[data-node-id='"
        <> (intToText . fromSqlKey $ k)
        <> "']/>"

handler ::
  Int64 ->
  Int64 ->
  Text ->
  Maybe Int ->
  AppM (Union '[WithStatus 200 (Html ()), WithStatus 204 NoContent])
handler pid nid clientTitle mwrap = do
  mnde <- runDb . queryNode $ nid
  case mnde >>= either (const Nothing) Just . nodeInProject pid of
    Nothing -> throwError err404 {errBody = "Node not found"}
    Just nde
      | pack (M.nodeTitle (entityVal nde)) == clientTitle ->
          respond (WithStatus @204 NoContent)
      | otherwise ->
          respond . WithStatus @200 . templateRefresh wrapWidth $ nde
  where
    wrapWidth = fromMaybe defaultWrapWidth mwrap
