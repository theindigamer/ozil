module Help.Ozil.App where

import Commons

import Help.Ozil.App.Cmd
import Help.Ozil.App.Core

import Help.Ozil.App.Config (FSEvent, toReactOrNotToReact)
import Help.Ozil.App.Startup (finishStartup)

import qualified Help.Page as Page
import qualified Help.Ozil.App.Default as Default

import Brick (App (..))

import qualified Brick
import qualified Brick.BChan as BChan
import qualified Brick.Widgets.Border as Border
import qualified Data.Text as T
import qualified Graphics.Vty as Vty
import qualified System.FSNotify as FSNotify

main :: IO ()
main = defaultMain $ \opts -> do
  (dp, cfg) <- finishStartup opts
  FSNotify.withManager $ \wm -> do
    chan <- BChan.newBChan maxChanSize
    saveConfig $ Brick.customMain gui (Just chan) oapp (newOState opts wm chan dp cfg)
  where
    gui = Vty.mkVty Vty.defaultConfig
    maxChanSize = 20
    saveConfig = void

oapp :: OApp
oapp = Brick.App
  { appDraw = \s -> [ui s]
  , appChooseCursor = Brick.showFirstCursor
  , appHandleEvent = handleEvent
  , appStartEvent = ozilStartEvent
  , appAttrMap = const $ Brick.attrMap Vty.defAttr []
  }

ozilStartEvent :: OState -> Brick.EventM OResource OState
ozilStartEvent s = case s ^. watch of
  Running _ -> pure s
  Uninitialized wm -> do
    sw <- liftIO $
      FSNotify.watchDir wm Default.configDir toReactOrNotToReact forwardEvent
    pure (set watch (Running sw) s)
  where
    forwardEvent :: FSEvent -> IO ()
    forwardEvent = BChan.writeBChan (getBChan s) . OEvent

handleEvent
  :: OState
  -> Brick.BrickEvent n OEvent
  -> Brick.EventM OResource (Brick.Next OState)
handleEvent s = \case
  KeyPress Vty.KEsc        -> stopProgram
  KeyPress (Vty.KChar 'q') -> stopProgram
  ev -> do
    let
      scrollAmt = case ev of
        KeyPress Vty.KDown       ->  1
        KeyPress (Vty.KChar 'j') ->  1
        KeyPress (Vty.KChar 'k') -> -1
        KeyPress Vty.KUp         -> -1
        _ -> 0
    when (scrollAmt /= 0)
      $ Brick.vScrollBy (Brick.viewportScroll TextViewport) scrollAmt
    Brick.continue s
  where
    stopProgram = do
      case s ^. watch of
        Running stopWatch -> liftIO stopWatch
        Uninitialized _ -> pure ()
      Brick.halt s

-- The UI should look like
--
-- +------  heading  ------+
-- |                       |
-- | blah                  |
-- |                       |
-- | blah                  |
-- |                       |
-- | blah                  |
-- |                       |
-- +-----------------------+
-- | Esc/q = Exit ...      |
-- +-----------------------+
--
-- ui :: (Show n, Ord n) => Brick.Widget n
ui
  :: (HasDoc s Page.DocPage, HasHeading s Text, HasLinkState s Page.LinkState)
  => s
  -> Brick.Widget OResource
ui s = Border.borderWithLabel (Brick.txt header) $
  body
  Brick.<=>
  Border.hBorder
  Brick.<=>
  Brick.txt "Esc/q = Exit  k/↑ = Up  j/↓ = Down"
  where
    header = T.snoc (T.cons ' ' (s ^. heading)) ' '
    body = Page.render (s ^. linkState) (s ^. doc)
      & Brick.viewport TextViewport Brick.Vertical
