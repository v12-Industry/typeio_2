{-# LANGUAGE OverloadedStrings #-}

module Platform.Build
  ( BuildInfo (..)
  , buildCommitKey
  , loadBuildInfo
  , resolveCommit
  , unknownCommit
  ) where

import Control.Exception (SomeException, try)
import Data.Aeson (ToJSON, object, toJSON, (.=))
import Data.Char (isHexDigit, isSpace)
import Data.List (dropWhileEnd)
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.Process (readProcessWithExitCode)

newtype BuildInfo = BuildInfo
  { commit :: String
  }
  deriving (Eq, Read, Show)

instance ToJSON BuildInfo where
  toJSON bi = object ["commit" .= commit bi]

unknownCommit :: String
unknownCommit = "UNKNOWN"

buildCommitKey :: String
buildCommitKey = "BUILD_COMMIT"

loadBuildInfo :: IO BuildInfo
loadBuildInfo = do
  injected <- lookupEnv buildCommitKey
  checkedOut <- gitHeadCommit
  pure . BuildInfo . resolveCommit injected $ checkedOut

resolveCommit :: Maybe String -> Maybe String -> String
resolveCommit injected checkedOut =
  fromMaybe unknownCommit . listToMaybe . mapMaybe commitHash $ [injected, checkedOut]

commitHash :: Maybe String -> Maybe String
commitHash = (>>= isCommitHash . trim)
  where
    isCommitHash h
      | length h == 40 && all isHexDigit h = Just h
      | otherwise = Nothing
    trim = dropWhileEnd isSpace . dropWhile isSpace

gitHeadCommit :: IO (Maybe String)
gitHeadCommit = do
  res <- try (readProcessWithExitCode "git" ["rev-parse", "HEAD"] "") :: IO (Either SomeException (ExitCode, String, String))
  pure $ case res of
    Right (ExitSuccess, out, _) -> Just out
    _ -> Nothing
