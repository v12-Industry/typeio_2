module Domain.System.Middleware.Logging.Common where

import Data.Bifunctor (bimap)
import Data.ByteString.Char8 (unpack)
import Data.CaseInsensitive (original)
import Data.HashMap.Strict (HashMap, fromList)
import Network.HTTP.Types (RequestHeaders)

hashMapHeaders :: RequestHeaders -> HashMap String String
hashMapHeaders =
  fromList
    . map (bimap (unpack . original) unpack)
