{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for the header's aggregate save-state
indicator.

The indicator derives its own state from htmx's request events rather
than being told: no field names it and no handler renders it. That
leaves exactly two things a route test can pin -- that the shell
ships all three states plus the script that switches between them, and
that the editable fields still declare themselves as saves, which is
the only part the indicator cannot work out on its own.

What the browser owns instead is whether those pieces actually produce
idle/saving/saved in order; that lives in the E2E suite, because it is
a behaviour of htmx, hyperscript and CSS together and no amount of
markup assertion implies it.
-}
module Domain.Project.Responder.Ui.ProjectManage.SaveStateSpec (spec) where

import Data.Int (Int64)
import Data.Text (Text, pack)
import Database.Persist.Sql (fromSqlKey)
import Integration.Support
  ( TestApp
  , bodyOf
  , countStr
  , httpGet
  , resetBetweenTests
  , seedProjectWithRootNode
  , shouldContainStr
  , shouldNotContainStr
  , statusOf
  , withTestApp
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestApp $
  beforeWith resetBetweenTests $ do
    describe "the Manage Project shell" $ do
      it "renders the save-state indicator in the header" $ \ta -> do
        body <- manageBody ta

        body `shouldContainStr` "id=\"save-state\""

      it "ships all three states, so none has to be fetched to be shown" $ \ta -> do
        body <- manageBody ta

        -- Idle reuses the same `.dot` the nav header's trailing slot
        -- holds on every other page, which is what stops the header
        -- shifting the first time something saves.
        body `shouldContainStr` "save-state-idle"
        body `shouldContainStr` "class=\"dot\""
        body `shouldContainStr` "save-state-pending"
        body `shouldContainStr` "class=\"loading\""
        body `shouldContainStr` "save-state-saved"

      it "carries the script that switches between them" $ \ta -> do
        body <- manageBody ta

        -- The indicator listens to htmx's own request events and filters
        -- them to elements that declare themselves saves. Both halves
        -- matter: without the filter, opening a node panel would put the
        -- header into "Saving...".
        body `shouldContainStr` "htmx:beforeRequest from body"
        body `shouldContainStr` "htmx:afterRequest from body"
        body `shouldContainStr` "data-saves"

      it "is not addressed by anyone else" $ \ta -> do
        body <- manageBody ta

        -- The point of the design: nothing swaps into this element, so
        -- no handler has to know it exists and no field has to name it.
        body `shouldNotContainStr` "hx-swap-oob"
        body `shouldNotContainStr` "hx-indicator"

    describe "the node-edit form" $
      it "marks every editable field as a save" $ \ta -> do
        (projectKey, rootKey) <- seedProjectWithRootNode ta

        body <- nodeEditBody ta (fromSqlKey rootKey) (fromSqlKey projectKey)

        -- Title, description and status. A field that loses this
        -- still saves and still updates its own indicator box, so
        -- the only symptom is a header that never reacts to it --
        -- which is why this is a count and not a presence check.
        countStr "data-saves" body `shouldBe` 3

manageBody :: TestApp -> IO String
manageBody ta = do
  resp <- httpGet ta "/ui/project/vw?projectId=1"
  statusOf resp `shouldBe` 200
  pure (bodyOf resp)

nodeEditBody :: TestApp -> Int64 -> Int64 -> IO String
nodeEditBody ta nid pid = do
  resp <- httpGet ta (nodeEditUrl nid pid)
  statusOf resp `shouldBe` 200
  pure (bodyOf resp)

nodeEditUrl :: Int64 -> Int64 -> Text
nodeEditUrl nid pid =
  "/ui/project/node/edit?projectId=" <> pack (show pid) <> "&nodeId=" <> pack (show nid)
