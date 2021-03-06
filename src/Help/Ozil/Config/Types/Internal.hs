{-# LANGUAGE DataKinds      #-}
{-# LANGUAGE KindSignatures #-}

-- | We use type families to model the configuration changing with time.
--
-- Once we have different versions, we will have ToJSON and FromJSON for each
-- version, and additional "upgrade" functions that convert a UserConfigV1_0
-- to a UserConfigV2_0 (for example).
--
-- Modules that are not under the Config.* umbrella shouldn't access the
-- internals directly. Instead they should use the optics provided in
-- Config.Types.
module Help.Ozil.Config.Types.Internal where

import Help.Ozil.KeyBinding

import Data.Aeson

import Control.Monad (guard)
import Data.Aeson.Types (typeMismatch)
import Data.HashMap.Strict (HashMap)
import Data.Kind (Type)
import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Help.Page (summaryToPath, DocPageSummary, PagePath)

import qualified Data.List.NonEmpty as NE

data Version = V1_0

instance Show Version where
  show V1_0 = "1.0"

type family ConfigF (v :: Version) :: Type
type instance ConfigF 'V1_0 = ConfigV1_0

type family UserConfigF (v :: Version) :: Type
type instance UserConfigF 'V1_0 = UserConfigV1_0

type family SystemInfoF (v :: Version) :: Type
type instance SystemInfoF 'V1_0 = SystemInfoV1_0

type family ChoiceF (v :: Version) :: Type
type instance ChoiceF 'V1_0 = ChoiceV1_0

data ConfigV1_0 = ConfigV1_0
  { _systemInfo :: !SystemInfoV1_0
  , _userConfig :: !UserConfigV1_0
  } deriving Show

data SystemInfoV1_0 = SystemInfoV1_0
  { _ozilConfigFileExists :: !(Maybe FilePath)
  , _ozilDbExists         :: () -- ^ Unused for now
  } deriving Show

type KeyBindings = HashMap Action (NonEmpty KeyBinding)

data UserConfigV1_0 = UserConfigV1_0
  { _savedPreferences :: HashMap Text ChoiceV1_0
  , _keyBindings      :: KeyBindings
  , _databasePath     :: () -- ^ Unused for now
  } deriving Show

instance FromJSON UserConfigV1_0 where
  parseJSON (Object o) = do
    v <- o .: "version"
    guard (v == show V1_0)
    UserConfigV1_0
      <$> o .: "saved-preferences"
      <*> o .: "key-bindings"
      <*> pure ()
  parseJSON invalid = typeMismatch "User Config" invalid

instance ToJSON UserConfigV1_0 where
  toJSON UserConfigV1_0{_savedPreferences, _keyBindings} = object
    [ "version" .= show V1_0
    , "saved-preferences" .= _savedPreferences
    , "key-bindings" .= _keyBindings
    ]

data ChoiceV1_0 = ChoiceV1_0
  { _options :: NonEmpty PagePath
  , _choice  :: Int
  } deriving Show

instance FromJSON ChoiceV1_0 where
  parseJSON (Object o) = do
    _options <- o .: "options"
    _choice  <- o .: "choice"
    guard (0 <= _choice && _choice < NE.length _options)
    pure ChoiceV1_0{_options, _choice}
  parseJSON invalid = typeMismatch "Choice" invalid

instance ToJSON ChoiceV1_0 where
  toJSON ChoiceV1_0{_options, _choice} =
    object ["options" .= _options, "choice" .= _choice]

mkChoice :: Int -> NonEmpty DocPageSummary -> ChoiceV1_0
mkChoice i dps = ChoiceV1_0 { _options = fmap summaryToPath dps, _choice = i }

getPagePath :: ChoiceV1_0 -> PagePath
getPagePath ChoiceV1_0{_options, _choice} = _options NE.!! _choice
