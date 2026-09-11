{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for the Manage Project view's own chrome.

This responder touches no database -- it renders the page shell the
graph and node panel are then loaded into -- so unlike its neighbours
here it needs no seeded fixtures. It lives in this suite because it is
a responder, and responders are covered here rather than in
@test\/@ (see @docs\/development\/unit-testing.md@).

What the assertions pin is the htmx wiring: attribute strings in a
Lucid template matching element ids the shell defines elsewhere,
which is exactly the pairing a compiler cannot check.
-}
module Domain.Project.Responder.Ui.ProjectManage.ViewSpec (spec) where

import qualified Data.ByteString.Lazy.Char8 as LC8
import Data.List (isInfixOf, isPrefixOf, tails)
import Domain.Project.Responder.Ui.ProjectManage.View (handleProjectManageView)
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
spec = describe "handleProjectManageView (integration)" $
  describe "the toolbar's back link" $ do
    it "renders a labelled way back to the project index" $ do
      body <- manageBody

      -- The wordmark in the shared nav header already navigates here.
      -- What this pins is the separate, labelled affordance: the
      -- wordmark is discoverable only by guessing that a logo is a
      -- link.
      body `shouldContainStr` "id=\"manage-toolbar\""
      body `shouldContainStr` "Back to projects"

    it "navigates by swapping the shell rather than following an href" $ do
      body <- manageBody

      -- A `<button>` driving an htmx swap into #container, matching how
      -- the wordmark moves between pages. An `<a href>` here would
      -- promise a full navigation the app never performs.
      body `shouldContainStr` "hx-get=\"/ui/projects/vw\""
      body `shouldContainStr` "hx-target=\"#container\""
      body `shouldNotContainStr` "<a href=\"/ui/projects/vw\""

    it "pushes the index's URL so the address bar keeps up" $ do
      body <- manageBody

      -- Without this the browser would still show the project's URL
      -- after landing on the index, and Back would return to a page
      -- the user is already looking at.
      body `shouldContainStr` "hx-push-url=\"true\""

    it "sits above #view rather than inside it" $ do
      body <- manageBody

      -- #view is a flex row that the graph container and the node
      -- panel divide between them, so a toolbar placed inside it would
      -- render as a third column beside the graph instead of a band
      -- above it.
      let toolbarAt = indexOfStr "id=\"manage-toolbar\"" body
          viewAt = indexOfStr "id=\"view\"" body
      (toolbarAt < viewAt) `shouldSatisfyWith` "expected #manage-toolbar to render before #view"

-- | GET the Manage Project view and hand its body back as a 'String'.
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

shouldContainStr :: String -> String -> Expectation
shouldContainStr haystack needle =
  (needle `isInfixOf` haystack)
    `shouldSatisfyWith` ("expected the rendered view to contain " <> show needle)

shouldNotContainStr :: String -> String -> Expectation
shouldNotContainStr haystack needle =
  not (needle `isInfixOf` haystack)
    `shouldSatisfyWith` ("expected the rendered view not to contain " <> show needle)

{- | Where @needle@ first occurs in @haystack@, or its length if it does
not occur at all -- which keeps an ordering assertion honest when the
element is missing entirely.
-}
indexOfStr :: String -> String -> Int
indexOfStr needle hay =
  length . takeWhile (not . (needle `isPrefixOf`)) . tails $ hay

{- | A plain 'shouldBe' on a 'Bool' reports "False /= True", which says
nothing about which string was missing; this keeps the reason in the
failure message.
-}
shouldSatisfyWith :: Bool -> String -> Expectation
shouldSatisfyWith True _ = pure ()
shouldSatisfyWith False msg = expectationFailure msg
