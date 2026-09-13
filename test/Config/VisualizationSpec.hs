{-# LANGUAGE OverloadedStrings #-}

module Config.VisualizationSpec (spec) where

import Config.Visualization
  ( Visualization (..)
  , VisualizationChoice (..)
  , chosenVisualization
  , defaultVisualization
  , parseVisualization
  , resolveVisualization
  , visualizationText
  )
import Data.Text (pack)
import Test.Hspec

spec :: Spec
spec = do
  describe "resolveVisualization" $ do
    it "takes the default when the parameter is absent" $
      -- An ordinary link with no parameter is not a mistake, so it is
      -- answered rather than corrected.
      resolveVisualization Nothing
        `shouldBe` AsRequested defaultVisualization

    it "uses a value it recognises" $ do
      resolveVisualization (Just "Rootless") `shouldBe` AsRequested Rootless
      resolveVisualization (Just "Orbital") `shouldBe` AsRequested Orbital

    it "falls back when the value is not a visualization" $
      resolveVisualization (Just "Radial")
        `shouldBe` FellBack defaultVisualization

    it "falls back on the wrong case, since the names are case-sensitive" $
      resolveVisualization (Just "orbital")
        `shouldBe` FellBack defaultVisualization

    it "falls back on an empty value rather than treating it as absent" $
      -- `?visualizationMode=` is a value that is present and does not
      -- parse. Answering it with the default silently would hide the
      -- mistake; falling back names it in the redirected URL.
      resolveVisualization (Just "")
        `shouldBe` FellBack defaultVisualization

    it "distinguishes absent from unparseable, which is the whole point" $
      -- Both end up drawing the default, but only one of them is worth
      -- telling the caller about.
      resolveVisualization Nothing
        `shouldNotBe` resolveVisualization (Just "nonsense")

    it "never falls back to something that would fall back again" $
      -- A redirect target that is itself invalid would loop.
      resolveVisualization (Just "nonsense")
        `shouldSatisfy` \c ->
          resolveVisualization (Just (pack (show (chosenVisualization c))))
            == AsRequested (chosenVisualization c)

  describe "chosenVisualization" $ do
    it "reads the visualization out of either outcome" $ do
      chosenVisualization (AsRequested Rootless) `shouldBe` Rootless
      chosenVisualization (FellBack Orbital) `shouldBe` Orbital

  describe "the Read/Show pair the parameter relies on" $ do
    it "round-trips every visualization through its own name" $
      -- The redirect writes `show viz` into the URL and the next request
      -- reads it back. If those ever disagree the redirect loops.
      mapM_
        ( \v ->
            resolveVisualization (Just (pack (show v)))
              `shouldBe` AsRequested v
        )
        [Rootless, Orbital]

  describe "visualizationText" $ do
    it "spells each visualization the way the app's URLs already do" $ do
      visualizationText Rootless `shouldBe` "Rootless"
      visualizationText Orbital `shouldBe` "Orbital"

    -- Stated rather than derived from `show`. A new constructor has to be
    -- given a URL spelling deliberately, and -Wall reports the gap.
    it "agrees with show for every visualization" $
      mapM_
        (\v -> visualizationText v `shouldBe` pack (show v))
        [minBound .. maxBound :: Visualization]

  describe "parseVisualization" $ do
    it "parses the canonical spelling" $
      parseVisualization "Rootless" `shouldBe` Just Rootless

    it "is case-insensitive, so a hand-typed URL still works" $ do
      parseVisualization "rootless" `shouldBe` Just Rootless
      parseVisualization "ORBITAL" `shouldBe` Just Orbital

    it "refuses a visualization that no longer exists" $
      parseVisualization "Layered" `shouldBe` Nothing

    it "refuses an empty value" $
      parseVisualization "" `shouldBe` Nothing

    it "round-trips every visualization through visualizationText" $
      mapM_
        (\v -> parseVisualization (visualizationText v) `shouldBe` Just v)
        [minBound .. maxBound :: Visualization]
