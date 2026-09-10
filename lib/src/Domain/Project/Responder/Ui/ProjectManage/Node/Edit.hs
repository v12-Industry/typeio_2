{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Edit where

import Common.Validation
  ( ValidationErr
  , isNotEmpty
  , isThere
  , runValidation
  , valRead
  , (.$)
  )
import Common.Web.Attributes
import Common.Web.Query (lookupVal)
import Control.Monad (forM_, unless)
import Control.Monad.Reader (ReaderT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either (EitherT, firstEitherT, hoistEither, hoistMaybe, runEitherT)
import Data.Aeson (object, (.=))
import Data.Int (Int64)
import Data.Text (Text, pack, unpack)
import Data.Text.Lazy (toStrict)
import Data.Text.Util (intToText)
import Data.Time (UTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Database.Esqueleto.Experimental (from, select, table)
import Database.Persist (Entity (..))
import Database.Persist.Sql (ConnectionPool, SqlBackend, fromSqlKey, runSqlPool)
import qualified Domain.Project.Model as M
import Domain.Project.Responder.Ui.ProjectManage.Node.Query
import Domain.Project.Responder.Ui.ProjectManage.Node.Validation
import Domain.Project.Responder.Ui.ProjectManage.SaveState (saveStateIndicator)
import Lucid
import Network.HTTP.Types (status200)
import Network.HTTP.Types.URI (QueryText, queryToQueryText)
import Network.Wai (Request, Response, ResponseReceived, queryString, responseLBS)

data NodeEditErr
  = InvalidParams [ValidationErr]
  | NodeNotFound

data GetNodeEditForm = GetNodeEditForm
  { formProjectId :: Maybe Text
  , formNodeId :: Maybe Text
  }

data GetNodeEditPayload = GetNodeEditPayload
  { payloadProjectId :: Int64
  , payloadNodeId :: Int64
  }

handleErr :: NodeEditErr -> Response
handleErr er = case er of
  (InvalidParams es) ->
    responseLBS
      status200
      [("Content-Type", "text/html")]
      . renderBS
      . templateInvalidParams
      $ es
  NodeNotFound -> do
    responseLBS
      status200
      [("Content-Type", "text/html")]
      . renderBS
      $ templateNodeNotFound

handleGetNodeEdit ::
  ConnectionPool ->
  Request ->
  (Response -> IO ResponseReceived) ->
  IO ResponseReceived
handleGetNodeEdit pl req respond = do
  rslt <- flip runSqlPool pl . runEitherT $ do
    pyld <-
      firstEitherT InvalidParams
        . validateForm
        $ form
    nde <-
      lift (queryNode . payloadNodeId $ pyld)
        >>= hoistMaybe NodeNotFound
        >>= ( firstEitherT InvalidParams
                . validateNodeProjectId (payloadProjectId pyld)
            )
    nsts <- lift queryNodeStatuses
    return (nde, nsts)
  case rslt of
    Left e -> respond $ handleErr e
    Right
      ( nde
        , nsts
        ) ->
        respond
          . responseLBS
            status200
            [("Content-Type", "text-html")]
          . renderBS
          . templateNodeEdit nsts
          $ nde
  where
    form =
      queryTextToForm
        . queryToQueryText
        . queryString
        $ req

formatUpdated :: UTCTime -> Text
formatUpdated = pack . formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S"

queryNodeStatuses :: ReaderT SqlBackend IO [Entity M.NodeStatus]
queryNodeStatuses = select . from $ table @M.NodeStatus

queryTextToForm :: QueryText -> GetNodeEditForm
queryTextToForm qt =
  GetNodeEditForm
    { formProjectId = lookupVal "projectId" qt
    , formNodeId = lookupVal "nodeId" qt
    }

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
      , hxPut_ "/ui/project/node/title"
      , hxPushUrl_ False
      , hxInclude_ "this"
      , hxTrigger_ "input changed delay:500ms"
      , hxVals'_ $
          object
            [ "projectId" .= (intToText . fromSqlKey . M.nodeProjectId $ nde)
            , "nodeId" .= (intToText . fromSqlKey $ k)
            ]
      , hxTarget_ "label[for=\"title\"] .indicator-box"
      , hxIndicator_ saveStateIndicator
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
      , hxPut_ "/ui/project/node/description"
      , hxPushUrl_ False
      , hxInclude_ "this"
      , hxTrigger_ "input changed delay:500ms"
      , hxVals'_ $
          object
            [ "projectId" .= (intToText . fromSqlKey . M.nodeProjectId $ nde)
            , "nodeId" .= (intToText . fromSqlKey $ k)
            ]
      , hxTarget_ "label[for=\"description\"] .indicator-box"
      , hxIndicator_ saveStateIndicator
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
          , hxPut_ "/ui/project/node/status"
          , hxPushUrl_ False
          , hxInclude_ "this"
          , hxTrigger_ "change"
          , hxVals'_ $
              object
                [ "projectId" .= (intToText . fromSqlKey . M.nodeProjectId $ nde)
                , "nodeId" .= (intToText . fromSqlKey $ k)
                ]
          , hxTarget_ "#status-indicator"
          , hxIndicator_ saveStateIndicator
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

validateForm ::
  Monad m =>
  GetNodeEditForm ->
  EitherT [ValidationErr] m GetNodeEditPayload
validateForm fm = hoistEither . runValidation id $ do
  pid <-
    formProjectId fm
      .$ unpack
      >>= isThere "Project id must be present"
      >>= isNotEmpty "Project id must have a value"
      >>= valRead "Project id must be valid integer"
  nid <-
    formNodeId fm
      .$ unpack
      >>= isThere "Node id must be present"
      >>= isNotEmpty "Node id must have a value"
      >>= valRead "Node id must be valid integer"
  return $ GetNodeEditPayload <$> pid <*> nid
