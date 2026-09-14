{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Detail where

import App.Env (AppM)
import App.Handler (renderNode)
import Common.Validation (ValidationErr)
import Control.Monad (forM_, unless)
import Data.Int (Int64)
import Data.Text (Text, pack)
import Data.Time (UTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Database.Persist (Entity (..))
import qualified Domain.Project.Model as M
import Lucid

formatUpdated :: UTCTime -> Text
formatUpdated = pack . formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S"

showNodeType :: Text -> Text
showNodeType typ = case typ of
  "project_root" -> "Root"
  "work" -> "Work"
  _ -> typ

templateNodeNotFound :: Html ()
templateNodeNotFound = do
  div_ [] "Node not found"

templateInvalidParams :: [ValidationErr] -> Html ()
templateInvalidParams es = do
  div_ [] $ do
    unless (null es) $ do
      div_ [class_ "error-messages"] $ do
        forM_ es $ p_ [class_ "error-message"] . toHtml

templateNodeDetail :: M.Node -> Html ()
templateNodeDetail nde = do
  header_ [] $
    h2_ [] (toHtml . pack . M.nodeTitle $ nde)
  section_ [] $
    p_ [] (toHtml . pack . M.nodeDescription $ nde)
  section_ [id_ "node-properties"] $ do
    article_ [] $ do
      span_ [class_ "property-label"] "Status:"
      span_ [class_ "property-value"] (toHtml . pack . M.unNodeStatusKey . M.nodeNodeStatusId $ nde)
    article_ [] $ do
      span_ [class_ "property-label"] "Type:"
      span_ [class_ "property-value"] (toHtml . pack . M.unNodeTypeKey . M.nodeNodeTypeId $ nde)
    article_ [] $ do
      span_ [class_ "property-label"] "Last Updated:"
      span_ [class_ "property-value"] (toHtml . formatUpdated . M.nodeUpdated $ nde)

handler :: Int64 -> Int64 -> AppM (Html ())
handler pid nid =
  renderNode
    pid
    nid
    templateNodeNotFound
    templateInvalidParams
    (pure . templateNodeDetail . entityVal)
