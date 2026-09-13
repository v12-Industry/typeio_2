{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Ui.ProjectIndex.List where

import Common.Web.Attributes
import Control.Monad (forM_)
import Control.Monad.Reader (ReaderT)
import Data.Text.Util (intToText)
import Database.Esqueleto.Experimental
  ( desc
  , from
  , fromSqlKey
  , limit
  , offset
  , orderBy
  , select
  , table
  )
import Database.Persist (Entity (..))
import Database.Persist.Postgresql (ConnectionPool)
import Database.Persist.Sql (SqlBackend, runSqlPool)
import qualified Domain.Project.Model as M
import Domain.Project.Responder.Ui.ProjectManage.Link
import Lucid
import Network.HTTP.Types (status200)
import Network.Wai (Response, ResponseReceived, responseLBS)

handleProjectList ::
  ConnectionPool ->
  (Response -> IO ResponseReceived) ->
  IO ResponseReceived
handleProjectList cp respond = do
  ps <- runSqlPool queryProjectVw cp
  tp <- case ps of
    [] -> pure templateEmptyProjects
    _ -> pure . templateList . map entityVal $ ps
  respond $
    responseLBS
      status200
      [("Content-Type", "text/html")]
      (renderBS tp)

queryProjectVw :: ReaderT SqlBackend IO [Entity M.ProjectVw]
queryProjectVw =
  select $ do
    p <- from $ table @M.ProjectVw
    orderBy [desc p.lastUpdated]
    limit 50
    offset 0
    pure p

templateEmptyProjects :: Html ()
templateEmptyProjects = html_ $ do
  h2_ "Create your first project."

templateList :: [M.ProjectVw] -> Html ()
templateList ps = div_ [id_ "view"] $ do
  div_ [id_ "project-index", class_ "card-grid"] $ do
    forM_ ps $ \p -> do
      div_
        [ id_ $ "project-item-" <> (intToText . fromSqlKey . M.projectVwProjectId $ p)
        , class_ "nav-target project-item"
        , hxGet_ (projectLink . fromSqlKey . M.projectVwProjectId $ p)
        , hxPushUrl_ True
        , hxSwap_ "innerHTML"
        , hxTarget_ "#container"
        , hxTrigger_ "click"
        ]
        $ do
          span_ [class_ "id"]
            $ toHtml
              . intToText
              . fromSqlKey
              . M.projectVwProjectId
            $ p
          div_ [class_ "content"] $ do
            h3_ (toHtml . M.projectVwTitle $ p)
            span_ (toHtml . M.projectVwDescription $ p)
            br_ []
            span_
              $ ("Updated: " <>)
                . toHtml
                . show
                . M.projectVwLastUpdated
              $ p
