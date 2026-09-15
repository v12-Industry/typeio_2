{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Ui.ProjectIndex.List where

import App.Env (AppM, runDb)
import App.Link
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
import Database.Persist.Sql (SqlBackend)
import qualified Domain.Project.Model as M
import Lucid

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

handler :: AppM (Html ())
handler = do
  ps <- runDb queryProjectVw
  pure $ case ps of
    [] -> templateEmptyProjects
    _ -> templateList . map entityVal $ ps
