{-# LANGUAGE OverloadedStrings #-}

module Common.Validation where

import Control.Monad (when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Maybe (MaybeT (..), hoistMaybe, runMaybeT)
import Control.Monad.Writer (Writer, runWriter, tell)
import Data.Maybe (fromMaybe)
import Data.Text (Text, pack)
import Text.Read (readMaybe)

type ErrMsg = Text
type ValidationErr = Text

validate :: Maybe a -> Writer [ValidationErr] (Maybe a)
validate = pure

(.$) :: Maybe a -> (a -> b) -> Writer [ValidationErr] (Maybe b)
m .$ f = pure $ fmap f m

isEq :: Eq a => a -> ErrMsg -> Maybe a -> Writer [ValidationErr] (Maybe a)
isEq val e m = runMaybeT $ do
  v <- hoistMaybe m
  when (val /= v) $ do
    lift $ tell [e]
  return v

isThere :: ErrMsg -> Maybe a -> Writer [ValidationErr] (Maybe a)
isThere e m =
  case m of
    Nothing -> tell [e] >> return Nothing
    Just x -> return $ Just x

isNotEmpty :: (Eq a, Monoid a) => ErrMsg -> Maybe a -> Writer [ValidationErr] (Maybe a)
isNotEmpty e m = runMaybeT $ do
  v <- hoistMaybe m
  when (v == mempty) $ do
    lift $ tell [e]
  return v

valRead ::
  Read b =>
  ErrMsg ->
  Maybe String ->
  Writer [ValidationErr] (Maybe b)
valRead _ Nothing = return Nothing
valRead e m = do
  let r = m >>= readMaybe
  case r of
    Nothing -> tell [e] >> return Nothing
    Just x -> return $ Just x

{- | Supply a value for a field that was legitimately absent.

The counterpart to 'isThere'. That one says "this must be present, and
its absence is an error"; this says "its absence is fine, and here is
what to use instead" — which is what an optional query parameter with a
default needs, and the one shape this module could not previously
express.

__It fills a missing value; it does not suppress a bad one.__ Errors
already recorded still fail the whole validation, so a field that was
present and unparseable stays an error even though this hands back a
value. That is the point: an absent field and a wrong one are different
things, and only the first should take the default.

__Put it last, after the checks that can fail.__ Everything upstream
still sees 'Nothing' for an absent field and passes it through
untouched; everything downstream would see the default and have nothing
to complain about. Ordering it first would quietly disable the rest of
the pipeline:

@
lookupVal "visualizationMode" qt
  '.$' unpack
  >>= 'valRead' "Invalid visualizationMode value"
  >>= orDefault defaultVisualization
@

Without this, a pipeline ending in an absent optional field hands
'runValidation' a @(Nothing, [])@ — no value and no errors — which it
reports as @"Unknown error in validation"@, because it is built for
fields that must end up present.
-}
orDefault :: a -> Maybe a -> Writer [ValidationErr] (Maybe a)
orDefault d m = return . Just $ fromMaybe d m

isBetween :: Ord a => a -> a -> Text -> Maybe a -> Writer [ValidationErr] (Maybe a)
isBetween minV maxV e m = runMaybeT $ do
  v <- hoistMaybe m
  when (v < minV || v > maxV) $ do
    lift $ tell [e]
  return v

runValidation ::
  ([ValidationErr] -> b) ->
  Writer [ValidationErr] (Maybe a) ->
  Either b a
runValidation f w =
  case res of
    (Just x, []) -> Right x
    (Nothing, []) -> Left $ f ["Unknown error in validation"]
    (_, es) -> Left $ f es
  where
    res = runWriter w

errcat :: String -> Text -> ErrMsg
errcat s t = pack s <> t
