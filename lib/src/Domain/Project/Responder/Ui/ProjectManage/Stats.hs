{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Ui.ProjectManage.Stats
  ( handler
  , templateProjectStats
  , queryProjectStats
  , queryStatusCounts
  , queryStatusVocabulary
  ) where

import App.Env (AppM, runDb)
import Control.Monad (forM_)
import Control.Monad.Reader (ReaderT)
import Data.Int (Int64)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text, pack)
import qualified Data.Text as T
import Data.Text.Util (intToText)
import Database.Esqueleto.Experimental
  ( Entity (..)
  , SqlBackend
  , Value (..)
  , asc
  , countRows
  , from
  , groupBy
  , orderBy
  , select
  , table
  , toSqlKey
  , val
  , where_
  , (!=.)
  , (==.)
  )
import qualified Domain.Project.Model as M
import Domain.Project.Stats
  ( ProjectStats (..)
  , StatusCount (..)
  , projectStats
  )
import Lucid

queryProjectStats :: Int64 -> ReaderT SqlBackend IO ProjectStats
queryProjectStats pid = do
  vocabulary <- queryStatusVocabulary
  counts <- queryStatusCounts pid
  return (projectStats vocabulary counts)

queryStatusVocabulary :: ReaderT SqlBackend IO [Text]
queryStatusVocabulary = do
  ss <- select $ do
    s <- from $ table @M.NodeStatus
    orderBy [asc s.nodeStatusId]
    pure s
  return [pack (M.nodeStatusNodeStatusId (entityVal s)) | s <- ss]

queryStatusCounts :: Int64 -> ReaderT SqlBackend IO (Map Text Int)
queryStatusCounts pid = do
  rows <- select $ do
    n <- from $ table @M.Node
    where_ (n.projectId ==. val (toSqlKey @M.Project pid))
    where_ (n.nodeTypeId !=. val (M.NodeTypeKey "project_root"))
    groupBy n.nodeStatusId
    pure (n.nodeStatusId, countRows)
  return $
    Map.fromList
      [ (pack (M.unNodeStatusKey k), c)
      | (Value k, Value c) <- rows
      ]

templateProjectStats :: ProjectStats -> Html ()
templateProjectStats stats = do
  statRow "stat-row" "Total nodes" (intToText (psTotal stats))
  forM_ (psByStatus stats) $ \(StatusCount st n) ->
    statRow "stat-row" (statusLabel st) (intToText n)
  statRow "stat-row stat-completion" "Completion" (intToText (psCompletion stats) <> "%")

statRow :: Text -> Text -> Text -> Html ()
statRow cls label value =
  div_ [class_ cls] $ do
    span_ [class_ "stat-label"] (toHtml label)
    span_ [class_ "stat-value"] (toHtml value)

statusLabel :: Text -> Text
statusLabel st = T.toUpper (T.take 1 st) <> T.drop 1 st

handler :: Int64 -> AppM (Html ())
handler pid = templateProjectStats <$> runDb (queryProjectStats pid)
