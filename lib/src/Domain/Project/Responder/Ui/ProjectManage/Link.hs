{-# LANGUAGE OverloadedStrings #-}

module Domain.Project.Responder.Ui.ProjectManage.Link where

import Config.Visualization (Visualization)
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

graphLink :: Int64 -> Visualization -> Text
graphLink pid viz =
  graphLinkFor pid
    <> "&visualizationMode="
    <> (pack . show $ viz)

graphLinkFor :: Int64 -> Text
graphLinkFor pid =
  "/ui/project/graph"
    <> "?projectId="
    <> intToText pid

projectLink :: Int64 -> Text
projectLink = (<>) "/ui/project/vw?projectId=" . intToText
