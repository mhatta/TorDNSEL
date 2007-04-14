-----------------------------------------------------------------------------
-- |
-- Module      : TorDNSEL.Config
-- Copyright   : (c) tup 2007
-- License     : Public domain (see LICENSE)
--
-- Maintainer  : tup.tuple@googlemail.com
-- Stability   : alpha
-- Portability : non-portable (pattern guards, GHC primitives)
--
-- Parsing configuration options passed on the command line and present in
-- config files.
--
-----------------------------------------------------------------------------

module TorDNSEL.Config (
    Config
  , ConfigValue(..)
  , parseConfig
  , parseConfigArgs
  , fillInConfig
  ) where

import TorDNSEL.Config.Internals