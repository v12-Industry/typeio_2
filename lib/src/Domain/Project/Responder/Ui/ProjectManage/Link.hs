{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Link where

import Data.Int (Int64)
import Data.Text (Text, pack)
import Data.Text.Util (intToText)

editLink :: Int64 -> Int64 -> Text
editLink nid pid =
  "/ui/project/node/edit"
    <> "?nodeId="
    <> intToText nid
    <> "&projectId="
    <> intToText pid

nodePanelLink :: Int64 -> Int64 -> Text
nodePanelLink nid pid =
  "/ui/project/node/panel"
    <> "?nodeId="
    <> intToText nid
    <> "&projectId="
    <> intToText pid

nodeDetailLink :: Int64 -> Int64 -> Text
nodeDetailLink nid pid =
  "/ui/project/node/detail"
    <> "?nodeId="
    <> intToText nid
    <> "&projectId="
    <> intToText pid

{- | The link a drawing uses to re-fetch one node's label after an edit.

@wrapWidth@ is how many characters per line the /asking shape/ fits, and
the response is wrapped to it. The endpoint is shared by every
visualization and their shapes are not the same size — a circle fits
fewer characters than the box it became in #178 — so without this the
label comes back re-wrapped to somebody else's shape.

The app has been here before: until #181 this link carried a
@layout=server@ flag for exactly this reason, and removing it was right
only because one renderer was left. Note what changed with the second
shape's return (#244): this says *how wide the shape is*, a fact the
caller knows, rather than *which renderer is asking*. Two visualizations
that happen to draw the same size pass the same number and want the same
answer, which is the test that tells a measurement from a flag.

@clientTitle@ goes in unescaped, so it stays last.
-}
nodeRefreshLink :: Int64 -> Int64 -> Int -> Text -> Text
nodeRefreshLink nid pid wrapWidth clientTitle =
  "/ui/project/node/refresh?nodeId="
    <> intToText nid
    <> "&projectId="
    <> intToText pid
    <> "&wrapWidth="
    <> (pack . show $ wrapWidth)
    <> "&clientTitle="
    <> clientTitle

graphLink :: Int64 -> Text
graphLink pid =
  "/ui/project/graph"
    <> "?projectId="
    <> intToText pid

projectLink :: Int64 -> Text
projectLink = (<>) "/ui/project/vw?projectId=" . intToText
