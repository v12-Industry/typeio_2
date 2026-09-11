{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for the header's aggregate save-state
indicator.

The indicator derives its own state from htmx's request events rather
than being told: no field names it and no handler renders it. That
leaves exactly two things a responder test can pin -- that the shell
ships all three states plus the script that switches between them, and
that the editable fields still declare themselves as saves, which is
the only part the indicator cannot work out on its own.

What the browser owns instead is whether those pieces actually produce
idle/saving/saved in order; that lives in the E2E suite, because it is
a behaviour of htmx, hyperscript and CSS together and no amount of
markup assertion implies it.
-}
module Domain.Project.Responder.Ui.ProjectManage.SaveStateSpec (spec) where

import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.Int (Int64)
import Data.List (isInfixOf, isPrefixOf, tails)
import Database.Persist.Sql (ConnectionPool, fromSqlKey)
import Domain.Project.Responder.Ui.ProjectManage.Node.Edit (handleGetNodeEdit)
import Domain.Project.Responder.Ui.ProjectManage.View (handleProjectManageView)
import Integration.Support
  ( resetBetweenTests
  , seedProjectWithRootNode
  , withTestDatabase
  )
import Network.HTTP.Types (methodGet)
import Network.Wai (Request, defaultRequest, queryString, requestMethod)
import Network.Wai.Test
  ( SResponse (..)
  , assertStatus
  , request
  , runSession
  )
import Test.Hspec

spec :: Spec
spec = do
  describe "the Manage Project shell" $ do
    it "renders the save-state indicator in the header" $ do
      body <- manageBody

      body `shouldContainStr` "id=\"save-state\""

    it "ships all three states, so none has to be fetched to be shown" $ do
      body <- manageBody

      -- Idle reuses the same `.dot` the nav header's trailing slot
      -- holds on every other page, which is what stops the header
      -- shifting the first time something saves.
      body `shouldContainStr` "save-state-idle"
      body `shouldContainStr` "class=\"dot\""
      body `shouldContainStr` "save-state-pending"
      body `shouldContainStr` "class=\"loading\""
      body `shouldContainStr` "save-state-saved"

    it "carries the script that switches between them" $ do
      body <- manageBody

      -- The indicator listens to htmx's own request events and filters
      -- them to elements that declare themselves saves. Both halves
      -- matter: without the filter, opening a node panel would put the
      -- header into "Saving...".
      body `shouldContainStr` "htmx:beforeRequest from body"
      body `shouldContainStr` "htmx:afterRequest from body"
      body `shouldContainStr` "data-saves"

    it "is not addressed by anyone else" $ do
      body <- manageBody

      -- The point of the design: nothing swaps into this element, so
      -- no handler has to know it exists and no field has to name it.
      body `shouldNotContainStr` "hx-swap-oob"
      body `shouldNotContainStr` "hx-indicator"

  aroundAll withTestDatabase $
    beforeWith resetBetweenTests $
      describe "the node-edit form" $
        it "marks every editable field as a save" $ \pool -> do
          (projectKey, rootKey) <- seedProjectWithRootNode pool

          body <- nodeEditBody pool (fromSqlKey rootKey) (fromSqlKey projectKey)

          -- Title, description and status. A field that loses this
          -- still saves and still updates its own indicator box, so
          -- the only symptom is a header that never reacts to it --
          -- which is why this is a count and not a presence check.
          countStr "data-saves" body `shouldBe` 3

-- | GET the Manage Project shell and hand its body back as a 'String'.
manageBody :: IO String
manageBody =
  runSession
    ( do
        resp <- request manageRequest
        assertStatus 200 resp
        pure . LC8.unpack . simpleBody $ resp
    )
    handleProjectManageView

manageRequest :: Request
manageRequest =
  defaultRequest
    { requestMethod = methodGet
    , queryString = [("projectId", Just "1")]
    }

-- | GET the node-edit form and hand its body back as a 'String'.
nodeEditBody :: ConnectionPool -> Int64 -> Int64 -> IO String
nodeEditBody pool nid pid =
  runSession
    ( do
        resp <- request (nodeEditRequest nid pid)
        assertStatus 200 resp
        pure . LC8.unpack . simpleBody $ resp
    )
    (handleGetNodeEdit pool)

nodeEditRequest :: Int64 -> Int64 -> Request
nodeEditRequest nid pid =
  defaultRequest
    { requestMethod = methodGet
    , queryString =
        [ ("nodeId", Just . C8.pack . show $ nid)
        , ("projectId", Just . C8.pack . show $ pid)
        ]
    }

shouldContainStr :: String -> String -> Expectation
shouldContainStr haystack needle =
  (needle `isInfixOf` haystack)
    `shouldSatisfyWith` ("expected the rendered markup to contain " <> show needle)

shouldNotContainStr :: String -> String -> Expectation
shouldNotContainStr haystack needle =
  not (needle `isInfixOf` haystack)
    `shouldSatisfyWith` ("expected the rendered markup not to contain " <> show needle)

{- | How many times @needle@ occurs in @haystack@.

Presence is not the assertion here: one field wired up and two left
behind reads exactly like all three to an @isInfixOf@ check.
-}
countStr :: String -> String -> Int
countStr needle = length . filter (needle `isPrefixOf`) . tails

{- | A plain 'shouldBe' on a 'Bool' reports "False /= True", which says
nothing about which string was missing; this keeps the reason in the
failure message.
-}
shouldSatisfyWith :: Bool -> String -> Expectation
shouldSatisfyWith True _ = pure ()
shouldSatisfyWith False msg = expectationFailure msg
