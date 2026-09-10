{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for the header's aggregate save-state
indicator.

The indicator is assembled from three separate responders that never
see each other: the page shell renders the element, the node-edit form
names it as its @hx-indicator@, and each field's save handler returns
an out-of-band fragment addressed to it. Those handlers' halves are
pinned in their own specs; what is left over -- and what nothing else
would catch -- is the shell and the form agreeing on the element's id.
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

    it "starts it idle, wearing the same dot every other page shows" $ do
      body <- manageBody

      -- The indicator occupies the nav header's trailing slot, which
      -- on every other view holds a plain `.dot`. Reusing that as the
      -- idle state is what keeps the header from shifting the first
      -- time something saves.
      body `shouldContainStr` "id=\"save-state-result\""
      body `shouldContainStr` "class=\"dot\""

    it "renders the pending state for htmx to reveal" $ do
      body <- manageBody

      -- "Saving..." ships with the page and is hidden by CSS until
      -- htmx puts `htmx-request` on the indicator, so no request is
      -- needed to produce it and nothing has to be injected at save
      -- time.
      body `shouldContainStr` "save-state-pending"
      body `shouldContainStr` "class=\"loading\""

    it "leaves the settled states to the handlers that own them" $ do
      body <- manageBody

      -- The shell never claims a save has happened: "Saved" only ever
      -- arrives out of band from a field's own handler.
      body `shouldNotContainStr` "save-state-saved"
      body `shouldNotContainStr` "hx-swap-oob"

  aroundAll withTestDatabase $
    beforeWith resetBetweenTests $
      describe "the node-edit form" $
        it "points every editable field at the header indicator" $ \pool -> do
          (projectKey, rootKey) <- seedProjectWithRootNode pool

          body <- nodeEditBody pool (fromSqlKey rootKey) (fromSqlKey projectKey)

          -- Title, description and status: one `hx-indicator` each, all
          -- naming the element the shell renders. A field that loses
          -- this still saves, and still updates its own indicator box,
          -- so the only visible symptom is a header that never says
          -- "Saving...".
          countStr "hx-indicator=\"#save-state\"" body `shouldBe` 3

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
