{-# LANGUAGE OverloadedStrings #-}

module Platform.Web.MiddlewareSpec (spec) where

import qualified Data.ByteString as BS
import Network.HTTP.Types (RequestHeaders)
import Network.Wai.Middleware.Static (CachingStrategy (..), FileMeta (..))
import Platform.Web.Middleware (staticCachingStrategy)
import Test.Hspec

-- The headers are defined inline with the strategy, so reach them the
-- way the middleware does: through the strategy value itself. Anything
-- other than CustomCaching is a real failure, not a test-setup detail
-- -- NoCaching sends nothing, and PublicStaticCaching carries a
-- max-age.
staticCacheHeaders :: FileMeta -> RequestHeaders
staticCacheHeaders = case staticCachingStrategy of
  CustomCaching f -> f
  _ -> error "expected staticCachingStrategy to be CustomCaching"

sampleMeta :: FileMeta
sampleMeta =
  FileMeta
    { fm_lastModified = "Mon, 07 Sep 2026 13:54:50 GMT"
    , fm_etag = "abc123"
    , fm_fileName = "static/styles/views/manage-project.css"
    }

spec :: Spec
spec = do
  describe "staticCacheHeaders" $ do
    it "tells the browser to revalidate on every request" $
      -- Static asset URLs carry no version or content hash, so a
      -- cached copy can only be trusted after asking. Without this the
      -- response carries no Cache-Control at all and browsers fall
      -- back to heuristic freshness, which can serve a stylesheet that
      -- predates the rules a page now depends on.
      lookup "Cache-Control" (staticCacheHeaders sampleMeta)
        `shouldBe` Just "no-cache"

    it "sends an ETag, so revalidating is a 304 rather than a resend" $
      -- `no-cache` without a validator would mean re-downloading every
      -- asset on every page load.
      lookup "ETag" (staticCacheHeaders sampleMeta)
        `shouldBe` Just "abc123"

    it "carries the file's own ETag rather than a fixed one" $
      lookup "ETag" (staticCacheHeaders sampleMeta {fm_etag = "def456"})
        `shouldBe` Just "def456"

    it "sends Last-Modified as a second validator" $
      lookup "Last-Modified" (staticCacheHeaders sampleMeta)
        `shouldBe` Just "Mon, 07 Sep 2026 13:54:50 GMT"

    it "never sends a max-age, which would reopen the stale window" $
      -- The bug this guards against is a cached stylesheet outliving
      -- the markup that depends on it. Any positive max-age reintroduces
      -- exactly that window.
      lookup "Cache-Control" (staticCacheHeaders sampleMeta)
        `shouldSatisfy` maybe False (not . BS.isInfixOf "max-age")
