-----------------------------------------------------------------------------
-- |
-- Module      : TorDNSEL.Control
-- Copyright   : (c) tup 2007
-- License     : Public domain (see LICENSE)
--
-- Maintainer  : tup.tuple@googlemail.com
-- Stability   : alpha
-- Portability : non-portable (pattern guards, concurrency, extended exceptions,
--                             GHC primitives)
--
-- Interfacing with Tor using the Tor control protocol, version 1. We support
-- fetching router descriptors and router status entries, including those sent
-- in asynchronous events that Tor generates when it receives new information
-- from directories.
--
-- See <https://tor.eff.org/svn/trunk/doc/spec/control-spec.txt> for details.
--
-----------------------------------------------------------------------------

module TorDNSEL.Control (
  -- * Connections
    Connection
  , withConnection
  , openConnection
  , waitForConnection
  , closeConnection

  -- * Commands
  , authenticate
  , getDescriptor
  , getAllDescriptors
  , getRouterStatus
  , getNetworkStatus
  , getCircuitStatus
  , getStreamStatus
  , setFetchUselessDescriptors
  , CircuitPurpose(..)
  , createCircuit
  , extendCircuit
  , attachStream
  , cedeStream
  , redirectStream
  , CloseCircuitFlags(..)
  , emptyCloseCircuitFlags
  , closeCircuit

  -- * Asynchronous events
  , EventHandler
  , registerEventHandlers
  , newDescriptorsEvent
  , networkStatusEvent
  , streamEvent
  , circuitEvent
  , addressMapEvent

  -- * Data types
  , CircuitID
  , CircuitStatus(..)
  , CircuitState(..)
  , StreamID
  , StreamStatus(..)
  , StreamState(..)
  , AddressMap(..)
  , Expiry(..)

  -- * Errors
  , ReplyCode
  , TorControlError(..)
  ) where

import TorDNSEL.Control.Internals
