module Main where

import Colog.Core.IO
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Effectful
import Effectful.Colog
import Effectful.Reader (ask, local, runReader)
import qualified Effectful.State.Local as Local
import qualified Effectful.State.Shared as Shared
import System.IO.Silently
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck
import Test.QuickCheck.Monadic

main :: IO ()
main = hspec $
  describe "Colog" $ do
    describe "runLog" testRunLog

testRunLog :: Spec
testRunLog = do
  prop "logs all pure messages" $ \msgs ->
    runPureEff (Shared.execState Seq.empty $ runLog (logMessagePure @String) (logMsgs msgs))
      === (msgs :: Seq String)
  prop "logs all stdout messages" $ \msgs ->
    monadicIO $ do
      stdout <- run $ capture_ $ runEff $ runLog logStringStdout (logMsgs msgs)
      pure $ stdout == unlines msgs
  prop "does not alter inner local state" $ \msgs1 msgs2 ->
    let app = do
          Local.modify @Int (+ 1)
          logMsgs msgs1
          Local.modify @Int (+ 1)
          logMsgs msgs2
          Local.modify @Int (+ 1)
     in runPureEff
          ( Shared.runState Seq.empty $
              runLog (logMessagePure @String) $
                Local.execState @Int 0 app
          )
          === (3, msgs1 <> msgs2 :: Seq String)
  prop "does not alter outer local state" $ \msgs1 msgs2 ->
    let app = do
          Local.modify @Int (+ 1)
          logMsgs msgs1
          Local.modify @Int (+ 1)
          logMsgs msgs2
          Local.modify @Int (+ 1)
     in runPureEff
          ( Local.runState @Int 0 $
              Shared.execState Seq.empty $
                runLog (logMessagePure @String) app
          )
          === (msgs1 <> msgs2 :: Seq String, 3)
  it "does work with 'Reader' effect" $
    let action = LogAction $ \msg -> do
          prefix <- ask @String
          unLogAction (logMessagePure @String) (prefix <> msg)
        app = do
          logMsg "first"
          local (const "local: ") (logMsg "second")
     in runPureEff
          (runReader "reader: " $ Shared.execState Seq.empty $ runLog action app)
          `shouldBe` Seq.fromList ["reader: first", "local: second"]