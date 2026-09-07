{-# LANGUAGE OverloadedStrings #-}

module Common.Web.QuerySpec (spec) where

import Common.Web.Query (lookupVal, setQueryParam)
import Test.Hspec

spec :: Spec
spec = do
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
