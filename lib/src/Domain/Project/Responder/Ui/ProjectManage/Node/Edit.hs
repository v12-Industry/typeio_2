{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Edit where

import App.Env (AppM, runDb)
import App.Handler (renderNode)
import App.Link (nodeDescriptionLink, nodeStatusLink, nodeTitleLink)
import Common.Validation (ValidationErr)
import Common.Web.Attributes
import Control.Monad (forM_, unless)
import Control.Monad.Reader (ReaderT)
import Data.Aeson (object, (.=))
import Data.Int (Int64)
import Data.Text (Text, pack)
import Data.Text.Lazy (toStrict)
import Data.Text.Util (intToText)
import Data.Time (UTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Database.Esqueleto.Experimental (from, select, table)
import Database.Persist (Entity (..))
import Database.Persist.Sql (SqlBackend, fromSqlKey)
import qualified Domain.Project.Model as M
import Lucid

formatUpdated :: UTCTime -> Text
formatUpdated = pack . formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S"

queryNodeStatuses :: ReaderT SqlBackend IO [Entity M.NodeStatus]
queryNodeStatuses = select . from $ table @M.NodeStatus

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

templateNodeEdit :: [Entity M.NodeStatus] -> Entity M.Node -> Html ()
templateNodeEdit nsts (Entity k nde) = do
  section_ [class_ "column-textarea form-section"] $ do
    label_ [class_ "indicator-label property-label", for_ "title"] $ do
      p_ "Title:"
      div_ [id_ "title-indicator", class_ "indicator-box"] empty
    input_
      [ type_ "text"
      , class_ "property-value"
      , id_ "title"
      , value_ (pack . M.nodeTitle $ nde)
      , name_ "title"
      , hxPut_ nodeTitleLink
      , hxPushUrl_ False
      , hxInclude_ "this"
      , hxTrigger_ "input changed delay:500ms"
      , hxVals'_ $
          object
            [ "projectId" .= (intToText . fromSqlKey . M.nodeProjectId $ nde)
            , "nodeId" .= (intToText . fromSqlKey $ k)
            ]
      , hxTarget_ "label[for=\"title\"] .indicator-box"
      , dataSaves_
      , h_ $
          "init set my.icount to 0 "
            <> "on input increment my.icount "
            <> "if my.icount mod 8 === 0 "
            <> "then set #title-indicator's innerHTML to '"
            <> (toStrict . renderText $ ld)
            <> "'"
      ]
  section_ [class_ "column-textarea form-section"] $ do
    label_ [class_ "indicator-label property-label", for_ "description"] $ do
      p_ "Description:"
      div_ [class_ "indicator-box"] empty
    textarea_
      [ id_ "description"
      , name_ "description"
      , hxPut_ nodeDescriptionLink
      , hxPushUrl_ False
      , hxInclude_ "this"
      , hxTrigger_ "input changed delay:500ms"
      , hxVals'_ $
          object
            [ "projectId" .= (intToText . fromSqlKey . M.nodeProjectId $ nde)
            , "nodeId" .= (intToText . fromSqlKey $ k)
            ]
      , hxTarget_ "label[for=\"description\"] .indicator-box"
      , dataSaves_
      , h_ "on input transition <label[for=\"description\"] .indicator-box i /> opacity to 0"
      ]
      (toHtml . M.nodeDescription $ nde)
  section_ [id_ "node-properties"] $ do
    article_ [] $ do
      span_ [] $ do
        label_ [for_ "status"] $ p_ "Status:"
        select_
          [ id_ "status"
          , class_ "property-value pill-dropdown"
          , name_ "status"
          , hxPut_ nodeStatusLink
          , hxPushUrl_ False
          , hxInclude_ "this"
          , hxTrigger_ "change"
          , hxVals'_ $
              object
                [ "projectId" .= (intToText . fromSqlKey . M.nodeProjectId $ nde)
                , "nodeId" .= (intToText . fromSqlKey $ k)
                ]
          , hxTarget_ "#status-indicator"
          , dataSaves_
          ]
          $ do
            forM_ nsts $ \nst ->
              let key = pack . M.unNodeStatusKey . entityKey $ nst
                  isCurrent = M.unNodeStatusKey (M.nodeNodeStatusId nde) == M.unNodeStatusKey (entityKey nst)
               in option_ (value_ key : [selected_ "selected" | isCurrent]) (toHtml key)
      div_ [id_ "status-indicator", class_ "indicator-box"] empty
  where
    empty = mempty :: Html ()
    ld :: Html ()
    ld = span_ [class_ "loading"] empty

handler :: Int64 -> Int64 -> AppM (Html ())
handler pid nid =
  renderNode
    pid
    nid
    templateNodeNotFound
    templateInvalidParams
    ( \nde -> do
        nsts <- runDb queryNodeStatuses
        pure (templateNodeEdit nsts nde)
    )
