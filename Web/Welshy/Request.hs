{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Web.Welshy.Request where

import Control.Applicative
import Control.Monad
import Control.Monad.Trans.Class
import Data.Aeson (FromJSON, fromJSON)
import qualified Data.Aeson as A
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.HashMap.Strict as HashMap
import Data.Maybe
import Data.Monoid
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.Lazy as TL
import Network.HTTP.Types
import Network.Wai
import Text.Read (readEither)

import Web.Welshy.Action
import Web.Welshy.Response

-----------------------------------------------------------------------

-- | Get a parameter captured by the route pattern.
--
--     * If the parameter does not exist, fails with an error.
--
--     * If the parameter was found but could not be parsed, 'pass' is called.
--       This means routes are typed to a degree.
--
capture :: Parsable a => Text -> Action a
capture k = (lookup k <$> captures) >>= \case
    Nothing  -> fail ("unknown capture: " ++ T.unpack k)
    Just raw -> case parseParam raw of
        Left  _ -> pass
        Right v -> return v

-- TODO: provide way to customize default response
-- | Get a query parameter.
--
--     * If the parameter does not exist or could not be parsed,
--       the action halts with HTTP status @400 Bad Request@.
--
queryParam :: Parsable a => Text -> Action a
queryParam k = (lookup k <$> queryParams) >>= \case
    Nothing  -> halt $ status badRequest400
    Just raw -> case parseParam raw of
        Left msg -> halt $ status badRequest400
        Right v  -> return v

-- | Like 'queryParam', but returns 'Nothing' if the parameter wasn't found.
--
--     * If the parameter could not be parsed,
--       the action halts with HTTP status @400 BadRequest@
--
maybeQueryParam :: Parsable a => Text -> Action (Maybe a)
maybeQueryParam k = (lookup k <$> queryParams) >>= \case
    Nothing  -> return Nothing
    Just raw -> case parseParam raw of
        Left  _ -> halt $ status badRequest400
        Right v -> return (Just v)

-- | Get a JSON parameter.
--
--     * If the request body is not a JSON dictionary,
--       or if the parameter does not exist or could not be parsed,
--       the action halts with HTTP status @400 Bad Request@.
--
jsonParam :: FromJSON a => Text -> Action a
jsonParam k = (HashMap.lookup k <$> jsonParams) >>= \case
    Nothing  -> halt $ status badRequest400
    Just raw -> case fromJSON raw of
        A.Error   _ -> halt $ status badRequest400
        A.Success v -> return v


-- | Like 'jsonParam', but returns 'Nothing' if the parameter wasn't found.
--
--     * If the request body is not a JSON dictionary,
--       the action halts with HTTP status @400 Bad Request@.
--
maybeJsonParam :: FromJSON a => Text -> Action (Maybe a)
maybeJsonParam k = (HashMap.lookup k <$> jsonParams) >>= \case
    Nothing  -> return Nothing
    Just raw -> case fromJSON raw of
        A.Error   _ -> halt $ status badRequest400
        A.Success v -> return (Just v)


-- | Parse the request body as a JSON object.
--
--     * If the body could not be parsed,
--       the action halts with HTTP status @400 Bad Request@.
--
jsonData :: FromJSON a => Action a
jsonData = A.decode <$> body >>= \case
    Nothing -> halt $ status badRequest400
    Just v  -> return v

-- | Get all JSON parameters.
--
--     * If the request body is not a JSON dictionary,
--       the action halts with HTTP status @400 Bad Request@.
--
jsonParams :: Action A.Object
jsonParams = Action $ \r s -> do
    case _jsonParams r of
        Nothing -> return $ Halt $ status badRequest400
        Just v  -> return $ Ok v s

-----------------------------------------------------------------------


-- TODO: rename Parseable to FromParam or FromText
-- | Minimal complete definition: 'parseParam'
class Parsable a where
    parseParam :: Text -> Either String a

    -- | The default definition uses 'parseParam' to parse
    -- comma-delimited lists.
    parseParamList :: Text -> Either String [a]
    parseParamList = mapM parseParam . T.split (== ',')

instance Parsable a => Parsable [a] where
    parseParam = parseParamList

instance Parsable Char where
    parseParam t = case T.unpack t of
                       [c] -> Right c
                       _   -> Left "parseParam Char: no parse"
    parseParamList = Right . T.unpack

instance Parsable Text    where parseParam = Right
instance Parsable TL.Text where parseParam = Right . TL.fromStrict
instance Parsable Int     where parseParam = readEither . T.unpack
instance Parsable Integer where parseParam = readEither . T.unpack
instance Parsable Bool    where parseParam = readEither . T.unpack
instance Parsable Double  where parseParam = readEither . T.unpack
instance Parsable Float   where parseParam = readEither . T.unpack

-----------------------------------------------------------------------


-- | Get the bearer token from an authorization header using the @Bearer@
-- authentication scheme (RFC 6750).
--
-- If the request does not have a (syntactically) valid authorization
-- header for the Bearer scheme, the action halts with HTTP status
-- @401 Unauthorized@.
bearerAuth :: Parsable a => Action a
bearerAuth = do
    headers <- requestHeaders <$> request
    maybe (halt $ status unauthorized401) return $ do
        credentials <- lookup hAuthorization headers
        let (scheme, raw) = BS.splitAt 7 credentials
        guard (scheme == "Bearer ")
        either (const Nothing) (Just) (parseParam $ T.decodeUtf8 raw)
