{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

import Web.Welshy

import Control.Applicative
import Control.Monad
import Control.Monad.Trans.Error
import Data.Monoid
import Data.Text (Text)
import qualified Data.Text as T
import Network.HTTP.Types

main = welshy 3000 $ do

{ ---------------------------------------------------------------------

; get "/test/:word" $ do
    word <- mzero <|> param "blah" <|> param "word" <|> param "wat"
    mzero
    unless (word == "hello") $ abortWith $ do
        status badRequest400
        text' $ mconcat [T.pack word, "? I don't think so..."]

    text' $ T.pack $ reverse word

} ---------------------------------------------------------------------
