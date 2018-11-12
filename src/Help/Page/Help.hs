{-# LANGUAGE ViewPatterns    #-}
{-# LANGUAGE RankNTypes      #-}
{-# LANGUAGE TemplateHaskell #-}

module Help.Page.Help where

import Commons

import Help.Ozil.App.Death (unreachableError)

import Control.Lens (makeLenses)
import Control.Monad.State.Strict
import Data.Char (isAlphaNum, isUpper)
import Text.Megaparsec hiding (State)
import Text.Megaparsec.Char

import qualified Control.Lens as L
import qualified Data.Text as T
import qualified Data.Vector.Generic as V

data HelpPage = HelpPage
  { _helpPageHeading  :: Optional
  , _helpPageSynopsis :: Optional -- ^ Equivalent to "usage"
  , _helpPageBody     :: Vector Item
  , _helpPageAnchors  :: UVector Int
  }

-- TODO: Maybe we should record offsets here?
data Item
  = Subcommand { _name :: Text, _description :: Text }
  | Flags      { _name :: Text, _description :: Text }
  | Plain Text
  deriving Show

data ItemIndent = ItemIndent { itemIndent :: !Int, descrIndent ::  !Int }
  deriving Show

data IndentGuess = IndentGuess
  { _flagIndent :: (Maybe ItemIndent, Maybe Int)
  , _subcommandIndent :: Maybe ItemIndent
  } deriving Show
makeLenses ''IndentGuess

type Parser = ParsecT () Text (State IndentGuess)

-- getColumn :: ParsecT () Text (State IndentGuess) Int
getColumn :: MonadParsec e s m => m Int
getColumn = unPos . sourceColumn <$> getPosition

runHelpParser :: Parser a -> Text -> (Either (ParseError Char ()) a, IndentGuess)
runHelpParser p txt = runState (runParserT p "" txt) (IndentGuess (Nothing, Nothing) Nothing)

evalHelpParser :: Parser a -> Text -> Either (ParseError Char ()) a
evalHelpParser a b = fst (runHelpParser a b)

eqIfJust :: Eq a => Maybe a -> a -> Bool
eqIfJust Nothing  _ = True
eqIfJust (Just y) x = x == y

twoColumnAlt
  :: (MonadParsec e Text m, MonadState IndentGuess m)
  => (Text -> Text -> Item)                  -- ^ Constructor
  -> m Text                                  -- ^ Item parser
  -> (IndentGuess -> [Int])                  -- ^ Item alignments
  -> L.Getter IndentGuess (Maybe ItemIndent) -- ^ Getter for description indent
  -> (Int -> Int -> IndentGuess -> m ())     -- ^ Save state at the end.
  -> m Item
twoColumnAlt ctor itemP trv lx changeStateIfNeeded = do
  space1
  itmCol <- getColumn
  s <- get
  let itmIndents = trv s
  guard (null itmIndents || itmCol `elem` itmIndents)
  itm <- itemP
  space1
  descCol <- getColumn
  descr <- getDescrGeneralP (fmap descrIndent (s ^. lx))
  changeStateIfNeeded itmCol descCol s
  pure (ctor itm descr)

getDescrGeneralP :: MonadParsec e Text m => Maybe Int -> m Text
getDescrGeneralP descIndent = do
  descCol <- getColumn
  guard (eqIfJust descIndent descCol)
  firstLine <- descrLine
  let nextLineP = try $ do
        space1
        descCol' <- getColumn
        guard (descCol' == descCol)
        descrLine
  nextLines <- many nextLineP
  pure (T.intercalate " " (firstLine : nextLines))
  where
    descrLine =
      lookAhead (notChar '[') *> takeWhile1P Nothing (/= '\n') <* newline

subcommandP :: Parser Item
subcommandP =
  twoColumnAlt
    Subcommand
    subcommandItemP
    (maybeToList . fmap itemIndent . view subcommandIndent)
    subcommandIndent
    (\itmCol descCol s -> case s ^. subcommandIndent of
        Nothing -> modify (set subcommandIndent (Just (ItemIndent itmCol descCol)))
        Just _  -> pure ()
    )

subcommandItemP :: Parser Text
subcommandItemP =
  lookAhead letterChar *> takeWhile1P Nothing (\c -> c == '-' || isAlphaNum c)

flagP :: Parser Item
flagP =
  twoColumnAlt
    Flags
    flagItemP
    (\s -> case s ^. flagIndent of
        (Nothing, _) -> []
        (Just ii, x) -> itemIndent ii : maybeToList x
    )
    (flagIndent . _1)
    (\itmCol descCol s -> case s ^. flagIndent of
        (Nothing, Nothing) -> save _1 (Just (ItemIndent itmCol descCol))
        (Just _,  Nothing) -> save _2 (Just itmCol)
        (Just _,  Just _)  -> pure ()
        (Nothing, Just _)  -> unreachableError
    )
   where save lx v = modify (set (flagIndent . lx) v)

flagItemP :: Parser Text
flagItemP = do
  first <- gobble (char '-')
  let next = try $ do
        space1
        gobble (satisfy (\c -> c == '[' || c == '<' || c == '-')
                <|> (satisfy isUpper *> satisfy isUpper))
  nextStuff <- many next
  let flags = T.intercalate " " (first : nextStuff)
  pure flags
  where
    gobble :: Parser a -> Parser Text
    gobble lk = lookAhead lk *> takeWhile1P Nothing (/= ' ')

singleLineP :: Parser Item
singleLineP = Plain . flip T.snoc '\n'
  <$> (takeWhile1P Nothing (/= '\n') <* optional newline)

helpP :: Parser [Item]
helpP =
  some (nl <|> try flagP <|> try subcommandP <|> singleLineP)
  <* optional eof
  where
    nl = Plain . T.singleton <$> char '\n'

-- TODO: Actually pick out indices for flags and subcommands.
parsePickAnchors :: HasCallStack => Text -> (Vector Item, UVector Int)
parsePickAnchors t = (, V.empty)
  $ V.fromList
  $ (\case Right x -> x; Left y -> error (show y))
  $ evalHelpParser helpP t
