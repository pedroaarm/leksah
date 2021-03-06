{-# LANGUAGE CPP #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
module IDE.Gtk.Package (
    projectRefreshNix
,   projectRefreshNix'
,   buildPackage

,   packageDoc
,   packageDoc'
,   packageClean
,   packageClean'
,   packageCopy
,   packageInstall
,   packageInstall'
,   packageRun
,   packageRunJavaScript
,   activatePackage
,   deactivatePackage

,   packageTest
,   packageTest'
,   packageBench
,   packageBench'
,   packageSdist
,   packageOpenDoc

,   getPackageDescriptionAndPath
,   getEmptyModuleTemplate
,   getModuleTemplate
,   ModuleLocation(..)
,   addModuleToPackageDescr
,   delModuleFromPackageDescr

,   backgroundBuildToggled
,   makeDocsToggled
,   runUnitTestsToggled
,   runBenchmarksToggled
,   nativeToggled
,   javaScriptToggled
,   makeModeToggled

,   debugStart
,   printBindResultFlag
,   breakOnErrorFlag
,   breakOnExceptionFlag

,   printEvldWithShowFlag
,   tryDebug
,   tryDebugQuiet
,   executeDebugCommand

,   idePackageFromPath'
,   writeGenericPackageDescription'

) where

import Prelude ()
import Prelude.Compat

import Control.Applicative ((<$>))
import Control.Exception (SomeException(..))
import Control.Lens ((%~))
import Control.Monad (when)
import Control.Monad.IO.Class (MonadIO(..))
import Control.Monad.Trans.Reader (ask)

import Data.GI.Base (new')
import GI.Gtk.Enums
       (WindowPosition(..), ResponseType(..), ButtonsType(..),
        MessageType(..))
import GI.Gtk.Objects.Dialog (constructDialogUseHeaderBar)
import GI.Gtk.Objects.MessageDialog
       (setMessageDialogText, constructMessageDialogButtons, setMessageDialogMessageType,
        MessageDialog(..))
import GI.Gtk.Objects.Widget (widgetDestroy)
import GI.Gtk.Objects.Window
       (setWindowWindowPosition, windowSetTransientFor)

import Graphics.UI.Editor.Parameters
       (dialogRun', dialogSetDefaultResponse', dialogAddButton')

import IDE.Core.State
       (native, runBenchmarks, runUnitTests, makeDocs, backgroundBuild,
        IDEAction, DebugAction, PackageAction, javaScript, makeMode,
        liftIDE, catchIDE, ipdPackageDir, ideMessage, MessageLevel(..),
        modifyIDE_, prefs)
import IDE.Gtk.State (getMainWindow)
import IDE.Utils.GUIUtils
       (__, setJavaScriptToggled, setDebugToggled, chooseDir,
        getBackgroundBuildToggled, getMakeDocs, getRunUnitTests,
        getRunBenchmarks, getNativeToggled, getJavaScriptToggled,
        getMakeModeToggled)
import IDE.Utils.CabalUtils (writeGenericPackageDescription')
import IDE.LogRef (logOutput)
import qualified Data.Text as T (pack)
import IDE.Utils.ExternalTool (runExternalTool')
import IDE.Package
import IDE.Pane.Log (getDefaultLogLaunch, showDefaultLogLaunch')

packageRun :: PackageAction
packageRun = interruptSaveAndRun $ packageRun' $ Just $ do
    window <- liftIDE getMainWindow
    md <- new' MessageDialog [
            constructDialogUseHeaderBar 0,
            constructMessageDialogButtons ButtonsTypeCancel]
    setMessageDialogMessageType md MessageTypeQuestion
    setMessageDialogText md $ __ "Package is configured to use GHCJS.  Would you like to remove --ghcjs from the configure flags and rebuild?"
    windowSetTransientFor md (Just window)
    _ <- dialogAddButton' md (__ "Use _GHC") (AnotherResponseType 1)
    dialogSetDefaultResponse' md (AnotherResponseType 1)
    setWindowWindowPosition md WindowPositionCenterOnParent
    resp <- dialogRun' md
    widgetDestroy md
    return $ resp == AnotherResponseType 1

packageRunJavaScript :: PackageAction
packageRunJavaScript = interruptSaveAndRun $ packageRunJavaScript' $ Just $ do
    window <- liftIDE getMainWindow
    md <- new' MessageDialog [
            constructDialogUseHeaderBar 0,
            constructMessageDialogButtons ButtonsTypeCancel]
    setMessageDialogMessageType md MessageTypeQuestion
    setMessageDialogText md $ __ "Would you like to enable the GHCJS as a build target and rebuild?"
    windowSetTransientFor md (Just window)
    _ <- dialogAddButton' md (__ "Enable _GHCJS") (AnotherResponseType 1)
    dialogSetDefaultResponse' md (AnotherResponseType 1)
    setWindowWindowPosition md WindowPositionCenterOnParent
    enableJS <- (== AnotherResponseType 1) <$> dialogRun' md
    widgetDestroy md
    when enableJS $ liftIDE $ setJavaScriptToggled True
    return enableJS

tryDebug :: DebugAction -> PackageAction
tryDebug = tryDebug' $ do
    window <- liftIDE getMainWindow
    md <- new' MessageDialog [
            constructDialogUseHeaderBar 0,
            constructMessageDialogButtons ButtonsTypeCancel]
    setMessageDialogMessageType md MessageTypeQuestion
    setMessageDialogText md $ __ "GHCi debugger is not running."
    windowSetTransientFor md (Just window)
    _ <- dialogAddButton' md (__ "_Start GHCi") (AnotherResponseType 1)
    dialogSetDefaultResponse' md (AnotherResponseType 1)
    setWindowWindowPosition md WindowPositionCenterOnParent
    enableDebug <- (== AnotherResponseType 1) <$> dialogRun' md
    widgetDestroy md
    when enableDebug $ liftIDE $ setDebugToggled True
    return enableDebug

packageCopy :: PackageAction
packageCopy = do
    package <- ask
    interruptSaveAndRun $ do
        logLaunch <- getDefaultLogLaunch
        showDefaultLogLaunch'

        catchIDE (do
            window      <- getMainWindow
            mbDir       <- liftIO $ chooseDir window (__ "Select the target directory") Nothing
            case mbDir of
                Nothing -> return ()
                Just fp -> do
                    let dir = ipdPackageDir package
                    runExternalTool' (__ "Copying")
                                    "cabal"
                                    ["copy", "--destdir=" <> T.pack fp]
                                    dir Nothing
                                    (logOutput logLaunch))
            (\(e :: SomeException) -> ideMessage High . T.pack $ show e)


backgroundBuildToggled :: IDEAction
backgroundBuildToggled = do
    toggled <- getBackgroundBuildToggled
    modifyIDE_ $ prefs %~ (\p -> p{backgroundBuild = toggled})

makeDocsToggled :: IDEAction
makeDocsToggled = do
    toggled <- getMakeDocs
    modifyIDE_ $ prefs %~ (\p -> p{makeDocs = toggled})

runUnitTestsToggled :: IDEAction
runUnitTestsToggled = do
    toggled <- getRunUnitTests
    modifyIDE_ $ prefs %~ (\p -> p{runUnitTests = toggled})

runBenchmarksToggled :: IDEAction
runBenchmarksToggled = do
    toggled <- getRunBenchmarks
    modifyIDE_ $ prefs %~ (\p -> p{runBenchmarks = toggled})

nativeToggled :: IDEAction
nativeToggled = do
    toggled <- getNativeToggled
    modifyIDE_ $ prefs %~ (\p -> p{native = toggled})

javaScriptToggled :: IDEAction
javaScriptToggled = do
    toggled <- getJavaScriptToggled
    modifyIDE_ $ prefs %~ (\p -> p{javaScript = toggled})

makeModeToggled :: IDEAction
makeModeToggled = do
    toggled <- getMakeModeToggled
    modifyIDE_ $ prefs %~ (\p -> p{makeMode = toggled})


