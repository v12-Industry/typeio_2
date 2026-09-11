{-# LANGUAGE OverloadedStrings #-}

module Common.Web.QuerySpec (spec) where

import Common.Web.Query (lookupVal, queryTextToText, setQueryParam)
import Test.Hspec

spec :: Spec
spec = do
  describe "queryTextToText" $ do
    it "has nothing to say about an empty query" $
      queryTextToText [] `shouldBe` Nothing

    it "keeps the parameters in the order they arrived in" $
      -- This rebuilds the URL the index shell re-requests, so a
      -- reordering here is a different URL than the one the user asked
      -- for.
      queryTextToText [("projectId", Just "4"), ("visualizationMode", Just "Rootless")]
        `shouldBe` Just "?projectId=4&visualizationMode=Rootless"

    it "does not leave a trailing separator" $
      -- A trailing `&` parses back as an extra nameless parameter, and
      -- anything appending to the URL afterwards inherits it.
      queryTextToText [("projectId", Just "4")] `shouldBe` Just "?projectId=4"

    it "renders a valueless parameter as a bare assignment" $
      queryTextToText [("flag", Nothing)] `shouldBe` Just "?flag="

    it "survives a query long enough for order to be visible" $
      -- Two parameters hide a reversal; five do not.
      queryTextToText
        [ ("projectId", Just "4")
        , ("visualizationMode", Just "Rootless")
        , ("viewX", Just "486.4")
        , ("viewY", Just "195.5")
        , ("viewScale", Just "1.2")
        ]
        `shouldBe` Just
          "?projectId=4&visualizationMode=Rootless&viewX=486.4&viewY=195.5&viewScale=1.2"

  describe "setQueryParam" $ do
    it "replaces an existing value" $
      setQueryParam "visualizationMode" "Orbital" [("visualizationMode", Just "Radial")]
        `shouldBe` [("visualizationMode", Just "Orbital")]

    it "keeps the parameter in its original position" $
      -- The corrected value goes back where it was, so a redirect URL
      -- reads like the one that was asked for rather than a reshuffle.
      setQueryParam "visualizationMode" "Orbital" [("projectId", Just "4"), ("visualizationMode", Just "Radial"), ("nodeId", Just "7")]
        `shouldBe` [("projectId", Just "4"), ("visualizationMode", Just "Orbital"), ("nodeId", Just "7")]

    it "leaves every other parameter untouched" $
      -- A redirect must not lose the project or node the caller asked
      -- for; that would send them somewhere they did not ask to go.
      lookupVal "projectId" (setQueryParam "visualizationMode" "Orbital" [("projectId", Just "4"), ("visualizationMode", Just "")])
        `shouldBe` Just "4"

    it "replaces a valueless parameter rather than leaving it bare" $
      setQueryParam "visualizationMode" "Orbital" [("visualizationMode", Nothing)]
        `shouldBe` [("visualizationMode", Just "Orbital")]

    it "replaces an empty value" $
      setQueryParam "visualizationMode" "Orbital" [("visualizationMode", Just "")]
        `shouldBe` [("visualizationMode", Just "Orbital")]

    it "appends when the parameter is not there at all" $
      setQueryParam "visualizationMode" "Orbital" [("projectId", Just "4")]
        `shouldBe` [("projectId", Just "4"), ("visualizationMode", Just "Orbital")]

    it "appends to an empty query" $
      setQueryParam "visualizationMode" "Orbital" []
        `shouldBe` [("visualizationMode", Just "Orbital")]

    it "replaces every copy, so a repeated parameter cannot survive" $
      -- A query may legally repeat a key. Leaving one of them behind
      -- would mean redirecting to a URL that is still wrong.
      setQueryParam "visualizationMode" "Orbital" [("visualizationMode", Just "Radial"), ("visualizationMode", Just "Bogus")]
        `shouldBe` [("visualizationMode", Just "Orbital"), ("visualizationMode", Just "Orbital")]

    it "is idempotent" $
      let q = [("projectId", Just "4"), ("visualizationMode", Just "Radial")]
          once = setQueryParam "visualizationMode" "Orbital" q
       in setQueryParam "visualizationMode" "Orbital" once `shouldBe` once
