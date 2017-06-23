{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module Highlight.Hrep.Run where

import Prelude ()
import Prelude.Compat

import Control.Exception (IOException)
import Data.ByteString (ByteString)
import Data.IntMap.Strict (IntMap, (!), fromList)
import Data.Maybe (maybeToList)
import Data.Monoid ((<>))
import Pipes (Producer, (>->), runEffect)
import Text.RE.PCRE
       (RE, SimpleREOptions(MultilineInsensitive, MultilineSensitive),
        (*=~), anyMatches, compileRegexWith)
import Text.RE.Replace (replaceAll)

import Highlight.Common.Color
       (colorForFileNumber, colorReset, colorVividBlueBold,
        colorVividCyanBold, colorVividGreenBold, colorVividMagentaBold,
        colorVividRedBold, colorVividWhiteBold, replaceInRedByteString)
import Highlight.Common.Error (handleErr)
import Highlight.Common.Options
       (IgnoreCase(IgnoreCase, DoNotIgnoreCase), CommonOptions(..),
        RawRegex(RawRegex))
import Highlight.Common.Pipes (stdinLines)
import Highlight.Hrep.Monad
       (FilenameHandlingFromFiles(..), HrepM, InputData, Output,
        compileHighlightRegexWithErr, createInputData, getIgnoreCaseM,
        getRawRegexM, handleInputData, outputConsumer, runHrepM,
        throwRegexCompileErr)

-- TODO: Combine a lot of these functions with the functions in Highlight.Run.

run :: CommonOptions -> IO ()
run opts = do
  eitherRes <- runHrepM opts prog
  either handleErr return eitherRes

prog :: HrepM ()
prog = do
  outputProducer <- hrepOutputProducer stdinLines
  runOutputProducer outputProducer

hrepOutputProducer
  :: Producer ByteString HrepM ()
  -> HrepM (Producer Output HrepM ())
hrepOutputProducer stdinProducer = do
  regex <- compileHighlightRegexWithErr
  inputData <- createInputData stdinProducer
  let outputProducer = getOutputProducer regex inputData
  return outputProducer

getOutputProducer
  :: RE
  -> InputData HrepM ()
  -> Producer Output HrepM ()
getOutputProducer regex inputData =
  handleInputData
    (handleStdinInput regex)
    (handleFileInput regex)
    handleError
    inputData

runOutputProducer :: Producer Output HrepM () -> HrepM ()
runOutputProducer producer =
  runEffect $ producer >-> outputConsumer

handleStdinInput
  :: RE -> ByteString -> [ByteString]
handleStdinInput regex input =
  formatNormalLine regex input

formatNormalLine :: RE -> ByteString -> [ByteString]
formatNormalLine regex =
  maybeToList . highlightMatchInRed regex

handleFileInput
  :: RE
  -> FilenameHandlingFromFiles
  -> ByteString
  -> Int
  -> ByteString
  -> [ByteString]
handleFileInput regex NoFilename _ _ input =
  formatNormalLine regex input
handleFileInput regex PrintFilename filePath fileNumber input =
  formatLineWithFilename regex fileNumber filePath input

-- TODO: The filename highlighting doesn't work here when none of the lines of
-- the file are output.
--
-- It would be nice to preprocess the input so that we don't get any lines that
-- do not match.
formatLineWithFilename
  :: RE -> Int -> ByteString -> ByteString -> [ByteString]
formatLineWithFilename regex fileNumber filePath input =
  case highlightMatchInRed regex input of
    Nothing -> []
    Just line ->
      [ colorForFileNumber fileNumber
      , filePath
      , colorVividWhiteBold
      ,  ": "
      , colorReset
      , line
      ]

handleError
  :: ByteString
  -> IOException
  -> Maybe IOException
  -> [ByteString]
handleError filePath _ (Just _) =
  [ "Error when trying to read file or directory \""
  , filePath
  , "\""
  ]
handleError filePath _ Nothing =
  [ "Error when trying to read file \""
  , filePath
  , "\""
  ]

highlightMatchInRed :: RE -> ByteString -> Maybe ByteString
highlightMatchInRed regex input =
  let matches = input *=~ regex
      didMatch = anyMatches matches
  in if didMatch
       then Just $ replaceAll replaceInRedByteString matches
       else Nothing
