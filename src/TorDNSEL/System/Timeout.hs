{-# OPTIONS -fglasgow-exts #-}
{-
The Glasgow Haskell Compiler License

Copyright 2004, The University Court of the University of Glasgow.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

- Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

- Neither name of the University nor the names of its contributors may be
used to endorse or promote products derived from this software without
specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE UNIVERSITY COURT OF THE UNIVERSITY OF
GLASGOW AND THE CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
UNIVERSITY COURT OF THE UNIVERSITY OF GLASGOW OR THE CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
DAMAGE.
-}

-------------------------------------------------------------------------------
-- |
-- Module      :  TorDNSEL.System.Timeout
-- Copyright   :  (c) The University of Glasgow 2007
-- License     :  BSD-style
--
-- Maintainer  :  libraries@haskell.org
-- Stability   :  experimental
-- Portability :  non-portable
--
-- Attach a timeout event to arbitrary 'IO' computations.
--
-------------------------------------------------------------------------------

module TorDNSEL.System.Timeout ( timeout ) where

import Prelude             (IO, Ord((<)), Eq((==)), Int, (.), otherwise, fmap)
import Data.Maybe          (Maybe(..))
import Control.Monad       (Monad(..), guard)
import Control.Concurrent  (forkIO, threadDelay, myThreadId, killThread)
import Control.Exception   (handleJust, throwDynTo, dynExceptions, bracket)
import Data.Dynamic        (Typeable, fromDynamic)
import Data.Unique         (Unique, newUnique)

-- An internal type that is thrown as a dynamic exception to
-- interrupt the running IO computation when the timeout has
-- expired.

data Timeout = Timeout Unique deriving (Eq, Typeable)

-- |Wrap an 'IO' computation to time out and return @Nothing@ in case no result
-- is available within @n@ microseconds (@1\/10^6@ seconds). In case a result
-- is available before the timeout expires, @Just a@ is returned. A negative
-- timeout interval means \"wait indefinitely\". When specifying long timeouts,
-- be careful not to exceed @maxBound :: Int@.
--
-- The design of this combinator was guided by the objective that @timeout n f@
-- should behave exactly the same as @f@ as long as @f@ doesn't time out. This
-- means that @f@ has the same 'myThreadId' it would have without the timeout
-- wrapper. Any exceptions @f@ might throw cancel the timeout and propagate
-- further up. It also possible for @f@ to receive exceptions thrown to it by
-- another thread.
--
-- A tricky implementation detail is the question of how to abort an @IO@
-- computation. This combinator relies on asynchronous exceptions internally.
-- The technique works very well for computations executing inside of the
-- Haskell runtime system, but it doesn't work at all for non-Haskell code.
-- Foreign function calls, for example, cannot be timed out with this
-- combinator simply because an arbitrary C function cannot receive
-- asynchronous exceptions. When @timeout@ is used to wrap an FFI call that
-- blocks, no timeout event can be delivered until the FFI call returns, which
-- pretty much negates the purpose of the combinator. In practice, however,
-- this limitation is less severe than it may sound. Standard I\/O functions
-- like 'System.IO.hGetBuf', 'System.IO.hPutBuf', 'Network.Socket.accept', or
-- 'System.IO.hWaitForInput' appear to be blocking, but they really don't
-- because the runtime system uses scheduling mechanisms like @select(2)@ to
-- perform asynchronous I\/O, so it is possible to interrupt standard socket
-- I\/O or file I\/O using this combinator.

timeout :: Int -> IO a -> IO (Maybe a)
timeout n f
    | n <  0    = fmap Just f
    | n == 0    = return Nothing
    | otherwise = do
        pid <- myThreadId
        ex  <- fmap Timeout newUnique
        handleJust (\e -> dynExceptions e >>= fromDynamic >>= guard . (ex ==))
                   (\_ -> return Nothing)
                   (bracket (forkIO (threadDelay n >> throwDynTo pid ex))
                            (killThread)
                            (\_ -> fmap Just f))
