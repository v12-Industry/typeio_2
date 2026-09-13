{-# LANGUAGE OverloadedStrings #-}

{- | Integration coverage for the Manage Project view's own chrome,
@GET /ui/project/vw@.

The route touches no database when it renders the shell -- it is the
page the graph and node panel are then loaded into -- so unlike its
neighbours here it needs no seeded fixtures. It lives in this suite
because it is a route, and routes are covered here rather than in
@test\/@ (see @docs\/development\/unit-testing.md@).

What the assertions pin is the htmx wiring: attribute strings in a
Lucid template matching element ids the shell defines elsewhere,
which is exactly the pairing a compiler cannot check.
-}
module Domain.Project.Responder.Ui.ProjectManage.ViewSpec (spec) where

import Integration.Support
  ( TestApp
  , bodyOf
  , httpGet
  , indexOfStr
  , resetBetweenTests
  , shouldContainStr
  , shouldNotContainStr
  , statusOf
  , withTestApp
  )
import Test.Hspec

spec :: Spec
spec = aroundAll withTestApp $
  beforeWith resetBetweenTests $
    describe "GET /ui/project/vw (integration)" $ do
      describe "the toolbar's back link" $ do
        it "renders a labelled way back to the project index" $ \ta -> do
          body <- manageBody ta

          -- The wordmark in the shared nav header already navigates here.
          -- What this pins is the separate, labelled affordance: the
          -- wordmark is discoverable only by guessing that a logo is a
          -- link.
          body `shouldContainStr` "id=\"manage-toolbar\""
          body `shouldContainStr` "Back to projects"

        it "navigates by swapping the shell rather than following an href" $ \ta -> do
          body <- manageBody ta

          -- A `<button>` driving an htmx swap into #container, matching how
          -- the wordmark moves between pages. An `<a href>` here would
          -- promise a full navigation the app never performs.
          body `shouldContainStr` "hx-get=\"/ui/projects/vw\""
          body `shouldContainStr` "hx-target=\"#container\""
          body `shouldNotContainStr` "<a href=\"/ui/projects/vw\""

        it "pushes the index's URL so the address bar keeps up" $ \ta -> do
          body <- manageBody ta

          -- Without this the browser would still show the project's URL
          -- after landing on the index, and Back would return to a page
          -- the user is already looking at.
          body `shouldContainStr` "hx-push-url=\"true\""

        it "sits above #view rather than inside it" $ \ta -> do
          body <- manageBody ta

          -- #view is a flex row that the graph container and the node
          -- panel divide between them, so a toolbar placed inside it would
          -- render as a third column beside the graph instead of a band
          -- above it.
          indexOfStr "id=\"manage-toolbar\"" body
            `shouldSatisfy` (< indexOfStr "id=\"view\"" body)

      describe "its parameters" $ do
        -- Every parameter on the route is Strict, so the page is not
        -- rendered around a value that could not be read.
        it "refuses a missing project id" $ \ta -> do
          resp <- httpGet ta "/ui/project/vw"
          statusOf resp `shouldBe` 400

        it "refuses a project id that is not a number" $ \ta -> do
          resp <- httpGet ta "/ui/project/vw?projectId=0x1"
          statusOf resp `shouldBe` 400

        -- The viewport's hyperscript appends viewX/viewY/viewScale to
        -- this base, so it has to come back rebuilt from what the route
        -- parsed rather than from the raw query string.
        it "carries a canonical view base" $ \ta -> do
          body <- manageBody ta

          body
            `shouldContainStr` "data-view-base=\"/ui/project/vw?projectId=1&amp;visualizationMode="

manageBody :: TestApp -> IO String
manageBody ta = do
  resp <- httpGet ta "/ui/project/vw?projectId=1"
  statusOf resp `shouldBe` 200
  pure (bodyOf resp)
