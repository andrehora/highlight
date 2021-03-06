{-# LANGUAGE CPP #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Highlight.Pipes where

import Prelude ()
import Prelude.Compat

import Control.Exception (throwIO, try)
import Control.Monad.IO.Class (MonadIO(liftIO))
import Data.ByteString (ByteString, hGetLine, hPutStr)
import Foreign.C.Error (Errno(Errno), ePIPE)
import GHC.IO.Exception
       (IOException(IOError), IOErrorType(ResourceVanished), ioe_errno,
        ioe_type)
import Pipes (Consumer', Producer', Proxy, await, each, yield)
import System.Directory (getDirectoryContents)
import System.FilePath ((</>))
import System.IO (Handle, stderr, stdin)

import Highlight.Util
       (closeHandleIfEOFOrThrow, openFilePathForReading)

-- | Read input from a 'Handle', split it into lines, and return each of those
-- lines as a 'ByteString' in a 'Producer'.
--
-- This function will close the 'Handle' if the end of the file is reached.
-- However, if an error was thrown while reading input from the 'Handle', the
-- 'Handle' is not closed.
--
-- Setup for examples:
--
-- >>> import Pipes.Prelude (toListM)
-- >>> import System.IO (IOMode(ReadMode), openBinaryFile)
-- >>> let goodFilePath = "test/golden/test-files/file2"
--
-- Examples:
--
-- >>> handle <- openBinaryFile goodFilePath ReadMode
-- >>> fmap head . toListM $ fromHandleLines handle
-- "Proud Pour is a wine company that funds solutions to local environmental"
fromHandleLines :: forall m. MonadIO m => Handle -> Producer' ByteString m ()
fromHandleLines handle = go
  where
    go :: Producer' ByteString m ()
    go = do
      eitherLine <- liftIO . try $ hGetLine handle
      case eitherLine of
        Left ioerr -> closeHandleIfEOFOrThrow handle ioerr
        Right line -> yield line *> go
{-# INLINABLE fromHandleLines #-}

-- | Call 'fromHandleLines' on 'stdin'.
stdinLines :: forall m. MonadIO m => Producer' ByteString m ()
stdinLines = fromHandleLines stdin
{-# INLINABLE stdinLines #-}

-- | Try calling 'fromHandleLines' on the 'Handle' obtained from
-- 'openFilePathForReading'.
--
-- Setup for examples:
--
-- >>> import Pipes (Producer)
-- >>> import Pipes.Prelude (toListM)
--
-- >>> let t a = a :: IO (Either IOException (Producer ByteString IO ()))
-- >>> let goodFilePath = "test/golden/test-files/file2"
-- >>> let badFilePath = "thisfiledoesnotexist"
-- >>> let handleErr err = error $ "got following error: " `mappend` show err
--
-- Example:
--
-- >>> eitherProducer <- t $ fromFileLines goodFilePath
-- >>> let producer = either handleErr id eitherProducer
-- >>> fmap head $ toListM producer
-- "Proud Pour is a wine company that funds solutions to local environmental"
--
-- Returns 'IOException' if there was an error when opening the file.
--
-- >>> eitherProducer <- t $ fromFileLines badFilePath
-- >>> either print (const $ return ()) eitherProducer
-- thisfiledoesnotexist: openBinaryFile: does not exist ...
fromFileLines
  :: forall m n x' x.
     (MonadIO m, MonadIO n)
  => FilePath
  -> m (Either IOException (Proxy x' x () ByteString n ()))
fromFileLines filePath = do
  eitherHandle <- openFilePathForReading filePath
  case eitherHandle of
    Left ioerr -> return $ Left ioerr
    Right handle -> return . Right $ fromHandleLines handle
{-# INLINABLE fromFileLines #-}

-- | Output 'ByteString's to 'stderr'.
--
-- If an 'ePIPE' error is thrown, then just 'return' @()@.  If any other error
-- is thrown, rethrow the error.
--
-- Setup for examples:
--
-- >>> :set -XOverloadedStrings
-- >>> import Pipes ((>->), runEffect)
--
-- Example:
--
-- >>> runEffect $ yield "hello" >-> stderrConsumer
-- hello
stderrConsumer :: forall m. MonadIO m => Consumer' ByteString m ()
stderrConsumer = go
  where
    go :: Consumer' ByteString m ()
    go = do
      bs <- await
      x  <- liftIO $ try (hPutStr stderr bs)
      case x of
        Left IOError { ioe_type = ResourceVanished, ioe_errno = Just ioe }
          | Errno ioe == ePIPE -> return ()
        Left  e  -> liftIO $ throwIO e
        Right () -> go
{-# INLINABLE stderrConsumer #-}

-- | Select all immediate children of the given directory, ignoring @\".\"@ and
-- @\"..\"@.
--
-- Throws an 'IOException' if the directory is not readable or (on Windows) if
-- the directory is actually a reparse point.
--
-- Setup for examples:
--
-- >>> import Data.List (sort)
-- >>> import Pipes.Prelude (toListM)
--
-- Examples:
--
-- >>> fmap (head . sort) . toListM $ childOf "test/golden/test-files"
-- "test/golden/test-files/dir1"
--
-- TODO: This could be rewritten to be faster by using the Windows- and
-- Linux-specific functions to only read one file from a directory at a time
-- like the actual
-- <https://hackage.haskell.org/package/dirstream-1.0.3/docs/Data-DirStream.html#v:childOf childOf>
-- function.
childOf :: MonadIO m => FilePath -> Producer' FilePath m ()
childOf path = do
  files <- liftIO $ getDirectoryContents path
  let filteredFiles = filter isNormalFile files
      fullFiles = fmap (path </>) filteredFiles
  each fullFiles
  where
    isNormalFile :: FilePath -> Bool
    isNormalFile file = file /= "." && file /= ".."
{-# INLINABLE childOf #-}
