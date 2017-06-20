
module Test.Golden where

import Data.ByteString (ByteString)
import Data.ByteString.Lazy (fromStrict)
import qualified Data.ByteString.Lazy as LByteString
import Data.Foldable (fold)
import Data.Monoid ((<>))
import Pipes (Pipe, Producer, (>->))
import Pipes.Prelude (mapFoldable, toListM)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Golden (goldenVsString)

import Highlight.Common.Options
       (InputFilename(InputFilename), RawRegex(RawRegex),
        commonOptionsInputFilenames, commonOptionsRawRegex,
        defaultCommonOptions)
import Highlight.Highlight.Monad
       (HighlightM, Output(OutputStderr, OutputStdout), runHighlightM)
import Highlight.Highlight.Options
       (defaultOptions, optionsCommonOptions)
import Highlight.Highlight.Run (progOutputProducer)


runHighlightStdout :: IO LByteString.ByteString
runHighlightStdout = do
  let opts =
        defaultOptions
          { optionsCommonOptions =
              defaultCommonOptions
                { commonOptionsRawRegex = RawRegex "or"
                , commonOptionsInputFilenames =
                    [InputFilename "test/golden/test-files/file1"]
                }
          }
  eitherByteStrings <- runHighlightM opts $ do
    outputProducer <- progOutputProducer
    toListM $ outputProducer >-> filterStdout
  case eitherByteStrings of
    Left err -> error $ "unexpected error: " <> show err
    Right byteStrings -> return . fromStrict $ fold byteStrings

filterStdout :: Monad m => Pipe Output ByteString m ()
filterStdout = mapFoldable f
  where
    f :: Output -> Maybe ByteString
    f (OutputStdout byteString) = Just byteString
    f (OutputStderr _) = Nothing

goldenTests :: TestTree
goldenTests = testGroup "golden tests" [highlightGoldenTests]

-- checkFrontEndApiType :: ExpectedFrontEndApi :~: FrontEndApi
-- checkFrontEndApiType = Refl

highlightGoldenTests :: TestTree
highlightGoldenTests = testGroup "highlight" [highlightSingleFile]

highlightSingleFile :: TestTree
highlightSingleFile =
  goldenVsString
    "single file"
    "test/golden/golden-files/highlight/single-file.stdout"
    runHighlightStdout