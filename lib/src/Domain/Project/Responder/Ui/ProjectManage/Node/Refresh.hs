{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Node.Refresh where

import Common.Validation
import Common.Web.Attributes
import Common.Web.Elements
import Data.Maybe (fromMaybe)
import Domain.Project.Graph.Types (LayoutConfig (..), defaultLayoutConfig)
import Domain.Project.Responder.Ui.ProjectManage.Node.Query
import Domain.Project.Responder.Ui.ProjectManage.Node.Validation
import Domain.Project.Visualization.Common (nodeContents, toGraphNode)
import Lucid

import qualified Domain.Project.Model as M

import Common.Web.Query (lookupVal)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Either
  ( EitherT
  , firstEitherT
  , hoistEither
  , hoistMaybe
  , runEitherT
  )
import qualified Data.ByteString.Lazy as B (fromStrict)
import Data.Int (Int64)
import Data.Text (Text, pack, unpack)
import Data.Text.Encoding (encodeUtf8)
import Data.Text.Util (intToText)
import Database.Esqueleto.Experimental
import Network.HTTP.Types (QueryText, queryToQueryText, status200, status204, status404, status500)
import Network.Wai (Application, Request (queryString), responseLBS)

data GetNodeRefreshErr
  = InvalidParams [ValidationErr]
  | MissingNode

data NodeRefreshComparisonResult = Same | Different

data GetNodeRefreshForm = GetNodeRefreshForm
  { formClientNodeTitle :: Maybe Text
  , formNodeId :: Maybe Text
  , formProjectId :: Maybe Text
  , formWrapWidth :: Maybe Text
  }

data GetNodeRefreshPayload = GetNodeRefreshPayload
  { payloadNodeId :: Int64
  , payloadProjectId :: Int64
  , payloadClientNodeTitle :: Text
  , payloadWrapWidth :: Int
  -- ^ Characters per line in the shape that asked. See 'defaultWrapWidth'.
  }

{- | What to wrap to when the request does not say.

The layered drawing's own box, so a request from before @wrapWidth@
existed — a page loaded across a deploy, say — still re-wraps to what it
was originally drawn at rather than to nothing.
-}
defaultWrapWidth :: Int
defaultWrapWidth = cfgLabelWidth defaultLayoutConfig

handleGetNodeRefresh :: ConnectionPool -> Application
handleGetNodeRefresh pl req rspnd = do
  rslt <- flip runSqlPool pl . runEitherT $ do
    pyld <-
      firstEitherT InvalidParams
        . validatePayload
        $ form
    nd <-
      lift (queryNode . payloadNodeId $ pyld)
        >>= hoistMaybe MissingNode
        >>= ( firstEitherT InvalidParams
                . validateNodeProjectId (payloadProjectId pyld)
            )
    let cmpr =
          if (pack . M.nodeTitle . entityVal $ nd)
            == payloadClientNodeTitle pyld
            then Same
            else Different
    pure (cmpr, nd, payloadWrapWidth pyld)
  case rslt of
    Left (InvalidParams es) ->
      rspnd
        . responseLBS
          status500
          [("Content-Type", "text/html")]
        $ foldr (\e acc -> acc <> (B.fromStrict . encodeUtf8 $ e) <> "\n") mempty es
    Left MissingNode ->
      rspnd
        . responseLBS
          status404
          [("Content-Type", "text/html")]
        $ "Node not found"
    Right (Different, nd, wrapWidth) ->
      rspnd
        . responseLBS
          status200
          [("Content-Type", "text/html")]
        . renderBS
        . templateRefresh wrapWidth
        $ nd
    Right (Same, _, _) ->
      rspnd
        . responseLBS
          status204
          []
        $ mempty
  where
    form =
      queryTextToForm
        . queryToQueryText
        . queryString
        $ req

queryTextToForm :: QueryText -> GetNodeRefreshForm
queryTextToForm qt =
  GetNodeRefreshForm
    { formProjectId = lookupVal "projectId" qt
    , formNodeId = lookupVal "nodeId" qt
    , formClientNodeTitle = lookupVal "clientTitle" qt
    , formWrapWidth = lookupVal "wrapWidth" qt
    }

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
    {- Flash every element the current drawing rendered for this node.

    Selects on `data-node-id` rather than `#node-<id>` (#234): an id
    names one element, and the orbital visualization draws a node once
    per dependent. Hyperscript applies `to <selector/>` to every match,
    so this line is unchanged in shape and now correct for both. -}
    nsel =
      "<[data-node-id='"
        <> (intToText . fromSqlKey $ k)
        <> "']/>"

validatePayload ::
  Monad m =>
  GetNodeRefreshForm ->
  EitherT [ValidationErr] m GetNodeRefreshPayload
validatePayload form =
  hoistEither . runValidation id $ do
    nid <-
      formNodeId form
        .$ unpack
        >>= isThere "Node id is required"
        >>= isNotEmpty "Node id must have value"
        >>= valRead "Node id must be valid integer"
    pid <-
      formProjectId form
        .$ unpack
        >>= isThere "Project id is required"
        >>= isNotEmpty "Project id must have value"
        >>= valRead "Project id must be valid integer"
    ttl <-
      formClientNodeTitle form
        .$ id
        >>= isThere "Node title is required"
        >>= isNotEmpty "Node title cannot be empty"
    {- Optional, so no `isThere`: `valRead` passes a Nothing straight
    through without recording an error, and only flags a value that is
    present but unparseable. An absent `wrapWidth` falls back to
    'defaultWrapWidth'; a nonsense one is still a bad request. -}
    wrp <-
      formWrapWidth form
        .$ unpack
        >>= valRead "Wrap width must be valid integer"
    return $
      GetNodeRefreshPayload
        <$> nid
        <*> pid
        <*> ttl
        <*> pure (fromMaybe defaultWrapWidth wrp)
