module Help.Ozil.App.Config
  ( getConfig
  , saveConfig
  )
  where

import Help.Ozil.App.Core
import Help.Ozil.App.Cmd
import Help.Ozil.App.Console.Text
import System.Directory

import Control.Lens.Extra ((<~=))
import Control.Monad (unless, when, join)
import Control.Monad.Extra (liftM2_1)
import Control.Monad.IO.Class (liftIO)
import Data.Yaml (prettyPrintParseException, decodeFileEither, encode)
import System.Exit (exitSuccess, die)
import Text.Printf (printf)

import qualified Control.Lens as L
import qualified Data.Text as T
import qualified Data.ByteString as BS
import qualified Help.Ozil.App.Default as Default
import qualified Help.Ozil.App.Config.Types as Conf

getConfig :: O ()
getConfig =
  foundConfigDir
    >>= deleteConfigDirIfApplicable
    >>= createConfigFileIfApplicable
    >>= readWriteConfig
    >>  checkDbExists
    >>= syncDbIfApplicable

foundConfigDir :: O Bool
foundConfigDir =
  Conf.configDirExists <~= liftIO (doesDirectoryExist =<< Default.configDir)

deleteConfigDirIfApplicable :: Bool -> O Bool
deleteConfigDirIfApplicable ozilDirExists = L.view optCommand >>= \case
  Config ConfigDelete -> delete >> liftIO exitSuccess
  Config ConfigReInit -> delete >> pure False
  _                   -> pure ozilDirExists
 where
  delete = when ozilDirExists $ do
    liftIO $ removePathForcibly =<< Default.configFilePath
    L.assign Conf.configDirExists False

createConfigFileIfApplicable :: Bool -> O Bool
createConfigFileIfApplicable ozilDirExists = L.view optCommand >>= \case
  Config ConfigInit   -> initAction *> liftIO exitSuccess
  Config ConfigReInit -> initAction *> ozilFileExists
  _                   -> do
    liftM2_1 unless ozilFileExists $ do
      create <- liftIO $ prompt True promptMsg
      when create initAction
    ozilFileExists
 where
  ozilFileExists :: O Bool
  ozilFileExists = Conf.configFileExists <~= liftIO
    ((ozilDirExists &&) <$> (doesFileExist =<< Default.configFilePath))
  initAction :: O ()
  initAction = ozilFileExists >>= \case
    True  -> liftIO $ die alreadyExistsMsg
    False -> do
      liftIO $ do
        createDirectoryIfMissing True =<< Default.configDir
        join
          $   BS.writeFile
          <$> Default.configFilePath
          <*> fmap (encode . L.view Conf.userConfig) Default.config
      L.assign Conf.configDirExists  True
      L.assign Conf.configFileExists True
  alreadyExistsMsg
    = "Error: configuration file already exists. \
      \Maybe you wanted to use ozil config reinit?"
  promptMsg = "Configuration directory not found. Should I initialize one?"

readWriteConfig :: Bool -> O ()
readWriteConfig = \case
  False -> undefined
  True  -> L.view optCommand >>= \case
    Config ConfigSync   -> readConfig *> syncConfig *> liftIO exitSuccess
    Config ConfigReInit -> readConfig *> syncConfig *> liftIO exitSuccess
    _                   -> readConfig
 where
  -- TODO: Implement this.
  syncConfig = pure ()
  readConfig = liftIO (decodeFileEither =<< Default.configFilePath) >>= \case
    Right cfg -> L.assign Conf.userConfig cfg
    Left err ->
      liftIO $ warn =<< configDecodeWarning (prettyPrintParseException err)
  configDecodeWarning s =
    T.pack
      <$> (   printf "Couldn't parse the config file %s.\n%s"
          <$> Default.configFilePath
          <*> pure s
          )

checkDbExists :: O Bool
checkDbExists = do
  p <- L.use (Conf.userConfig . Conf.databasePath)
  (Conf.systemInfo . Conf.ozilDbExists) <~= liftIO (doesFileExist p)

syncDbIfApplicable :: Bool -> O ()
syncDbIfApplicable dbExists = undefined

saveConfig :: O ()
saveConfig = undefined
