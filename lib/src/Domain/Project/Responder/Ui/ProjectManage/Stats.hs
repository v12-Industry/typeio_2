{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Ui.ProjectManage.Stats
  ( handleGetProjectStats
  , templateProjectStats
  , queryStatusCounts
  , queryStatusVocabulary
  ) where

import Common.Validation
  ( ValidationErr
  , isNotEmpty
  , isThere
  , runValidation
  , valRead
  , (.$)
  )
import Common.Web.Query (lookupVal)
import Control.Monad (forM_)
import Control.Monad.Reader (ReaderT)
import Data.Int (Int64)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text, pack, unpack)
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
import Database.Persist.Sql (ConnectionPool, runSqlPool)
import qualified Domain.Project.Model as M
import Domain.Project.Stats
  ( ProjectStats (..)
  , StatusCount (..)
  , projectStats
  )
import Lucid
import Network.HTTP.Types.Status (status200, status400)
import Network.HTTP.Types.URI (QueryText, queryToQueryText)
import Network.Wai (Application, queryString, responseLBS)

newtype GetProjectStatsForm = GetProjectStatsForm
  { formProjectId :: Maybe Text
  }

handleGetProjectStats :: ConnectionPool -> Application
handleGetProjectStats pl req respond =
  case pyld of
    Left _ ->
      respond
        . responseLBS status400 []
        $ "Error"
    Right pid -> do
      stats <- flip runSqlPool pl $ do
        vocabulary <- queryStatusVocabulary
        counts <- queryStatusCounts pid
        return (projectStats vocabulary counts)
      respond
        . responseLBS status200 []
        . renderBS
        . templateProjectStats
        $ stats
  where
    pyld =
      validateForm
        . queryTextToForm
        . queryToQueryText
        . queryString
        $ req

queryTextToForm :: QueryText -> GetProjectStatsForm
queryTextToForm qt =
  GetProjectStatsForm
    { formProjectId = lookupVal "projectId" qt
    }

validateForm :: GetProjectStatsForm -> Either [ValidationErr] Int64
validateForm fm = runValidation id $ do
  pid <-
    formProjectId fm
      .$ unpack
      >>= isThere "Project id must be present"
      >>= isNotEmpty "Project id must have a value"
      >>= valRead "Project id must be valid integer"
  return pid

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
