{-# LANGUAGE TypeSynonymInstances, OverlappingInstances #-}

-----------------------------------------------------------------------------
-- |
-- Module      : TorDNSEL.Log.Internals
-- License     : Public domain (see LICENSE)
--
-- Maintainer  : tup.tuple@googlemail.com
-- Stability   : alpha
-- Portability : non-portable (concurrency, extended exceptions,
--                             type synonym instances, overlapping instances)
--
-- /Internals/: should only be imported by the public module and tests.
--
-- Implements a logger thread and functions to log messages, reconfigure the
-- logger, and terminate the logger.
--
-----------------------------------------------------------------------------

-- #not-home
module TorDNSEL.Log.Internals where

import Prelude hiding (log)
import Control.Concurrent.Chan (Chan, newChan, writeChan, readChan)
import Control.Concurrent.MVar
  (MVar, newEmptyMVar, newMVar, takeMVar, tryPutMVar, readMVar, swapMVar)
import qualified Control.Exception as E
import Control.Monad (when, liftM2)
import Control.Monad.Fix (fix)
import Control.Monad.Trans (MonadIO, liftIO)
import Data.Time (UTCTime, getCurrentTime)
import System.IO
  (Handle, stdout, stderr, openFile, IOMode(AppendMode), hFlush, hClose)
import System.IO.Unsafe (unsafePerformIO)

import TorDNSEL.Control.Concurrent.Link
import TorDNSEL.Control.Concurrent.Util
import TorDNSEL.Util

-- | The logging configuration.
data LogConfig = LogConfig
  { minSeverity :: !Severity  -- ^ Minimum severity level to log
  , logTarget   :: !LogTarget -- ^ Where to send log messages
  , logEnabled  :: !Bool      -- ^ Is logging enabled?
  } deriving Show

-- | Where log messages should be sent.
data LogTarget = ToStdOut | ToStdErr | ToFile FilePath
  deriving Eq

instance Show LogTarget where
  show ToStdErr    = "stderr"
  show ToStdOut    = "stdout"
  show (ToFile fp) = show fp

-- | Open a handle associated with a given 'LogTarget' and pass it to an 'IO'
-- action, ensuring that the handle is closed or flushed as appropriate when the
-- action terminates. Exceptions generated by the action are re-thrown.
withLogTarget :: LogTarget -> (Handle -> IO a) -> IO a
withLogTarget ToStdOut    = E.bracket (return stdout) hFlush
withLogTarget ToStdErr    = E.bracket (return stderr) hFlush
withLogTarget (ToFile fp) = E.bracket (openFile fp AppendMode) hClose

-- | An internal type for messages sent to the logger.
data LogMessage
  = Log UTCTime Severity ShowS                   -- ^ A log message
  | Reconfigure (LogConfig -> LogConfig) (IO ()) -- ^ Reconfigure the logger
  | Terminate ExitReason -- ^ Terminate the logger gracefully

-- | Logging severities.
data Severity = Debug | Info | Notice | Warn | Error
  deriving (Eq, Ord, Show)

-- | The logger's 'ThreadId' and channel, if it is running.
logger :: MVar (Maybe (ThreadId, Chan LogMessage))
{-# NOINLINE logger #-}
logger = unsafePerformIO $ newMVar Nothing

-- | If the logger is running, invoke an 'IO' action with its 'ThreadId' and
-- channel.
withLogger :: (ThreadId -> Chan LogMessage -> IO ()) -> IO ()
withLogger io = readMVar logger >>= flip whenJust (uncurry io)

-- | A handle to the logger thread.
newtype Logger = Logger ThreadId

instance Thread Logger where
  threadId (Logger tid) = tid

-- | Start the global logger with an initial 'LogConfig', returning a handle to
-- it. Link the logger to the calling thread. If the logger exits before fully
-- starting, throw its exit signal in the calling thread.
startLogger :: LogConfig -> IO Logger
startLogger config = do
  err <- newEmptyMVar
  let putResponse = (>> return ()) . tryPutMVar err
  tid <- forkLinkIO $ do
    curLogger@(_,logChan) <- liftM2 (,) myThreadId newChan
    setTrapExit . const $ writeChan logChan . Terminate
    E.bracket_ (swapMVar logger $ Just curLogger) (swapMVar logger Nothing) $
      flip fix (config, putResponse Nothing) $ \resetLogger (conf, signal) ->
        (resetLogger =<<) . withLogTarget (logTarget conf) $ \handle -> do
          signal
          fix $ \nextMsg -> do
            msg <- readChan logChan
            case msg of
              Log time severity text -> do
                when (logEnabled conf && severity >= minSeverity conf) $ do
                  hCat handle (showUTCTime time) " [" severity "] " text '\n'
                  hFlush handle
                nextMsg
              Reconfigure reconf newSignal -> return (reconf conf, newSignal)
              Terminate reason -> exit reason
  withMonitor tid putResponse $
    takeMVar err >>= flip whenJust E.throwIO
  return $ Logger tid

-- | Implements the variable parameter support for 'log'.
class LogType r where
  log' :: CatArg a => ShowS -> Severity -> a -> r

instance MonadIO m => LogType (m a) where
  log' str sev arg = liftIO $ do
    now <- getCurrentTime
    withLogger $ \_ logChan -> do
      writeChan logChan (Log now sev (cat' str arg))
    return undefined -- to omit type annotations in do blocks

instance LogType (Severity, ShowS) where
  log' str sev arg = (sev, cat' str arg)

instance (CatArg a, LogType r) => LogType (a -> r) where
  log' str sev arg = log' (cat' str arg) sev

-- | Log a message asynchronously.
log :: (CatArg a, LogType r) => Severity -> a -> r
log = log' id

-- | Reconfigure the logger synchronously with the given function. If the logger
-- exits abnormally before reconfiguring itself, throw its exit signal in the
-- calling thread.
reconfigureLogger :: (LogConfig -> LogConfig) -> IO ()
reconfigureLogger reconf =
  withLogger $ \tid logChan ->
    sendSyncMessage (writeChan logChan . Reconfigure reconf) tid

-- | Terminate the logger gracefully: process any pending messages, flush the
-- log handle, and close the handle when logging to a file. The optional
-- parameter specifies the amount of time in microseconds to wait for the thread
-- to terminate. If the thread hasn't terminated by the timeout, an uncatchable
-- exit signal will be sent.
terminateLogger :: Maybe Int -> IO ()
terminateLogger mbWait =
  withLogger $ \tid logChan ->
    terminateThread mbWait tid (writeChan logChan $ Terminate Nothing)
