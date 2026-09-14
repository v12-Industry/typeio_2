module Environment.Logging where

import Control.Monad.Cont (ContT (..))
import Data.ByteString.Char8 (pack)
import Data.Time.Clock (getCurrentTime)
import Logging.Core (EntryLog (..), toEntryLog)
import System.Log.FastLogger
  ( FormattedTime
  , LogType' (LogStdout)
  , withTimedFastLogger
  )

getFormattedTime :: IO FormattedTime
getFormattedTime = pack . show <$> getCurrentTime

withLogger :: ContT r IO EntryLog
withLogger =
  toEntryLog
    <$> ContT (withTimedFastLogger getFormattedTime (LogStdout 10))
