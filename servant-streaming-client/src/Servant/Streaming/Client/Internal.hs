{-# OPTIONS_GHC -fno-warn-orphans #-}

module Servant.Streaming.Client.Internal where

import Control.Monad
import           Control.Monad.Trans.Resource (ResourceT, runResourceT, runInternalState, getInternalState)
import qualified Data.ByteString              as BS
import           Data.Proxy                   (Proxy (Proxy))
import qualified Network.HTTP.Media           as M
import           Servant.API                  hiding (Stream)
import           Servant.Client.Core
import Data.IORef
import           Servant.Streaming
import           Streaming
import qualified Streaming.Prelude            as S

instance (HasClient m subapi, RunClient m )
    => HasClient m (StreamBody contentTypes :> subapi) where
  type Client m (StreamBody contentTypes :> subapi)
    = (M.MediaType, Stream (Of BS.ByteString) (ResourceT IO) ())
      -> Client m subapi
  clientWithRoute pm _ req (mtype, body)
    = clientWithRoute
        pm
        (Proxy :: Proxy subapi)
        req { requestBody = Just (RequestBodyStreamChunked body', mtype) }
    where
      body' :: (IO BS.ByteString -> IO ()) -> IO ()
      body' write = runResourceT $ do
        ref <- liftIO $ newIORef body
        is <- getInternalState
        let popper :: IO BS.ByteString
            popper = do
              rsrc <- readIORef ref
              mres <- runInternalState (S.uncons rsrc) is
              case mres of
                Nothing -> return BS.empty
                Just (bs, str)
                  | BS.null bs -> writeIORef ref str >> popper
                  | otherwise -> writeIORef ref str >> return bs
        liftIO $ write popper

instance (RunClient m )
    => HasClient m (StreamResponse verb status contentTypes) where
  type Client m (StreamResponse verb status contentTypes)
    = m (Stream (Of BS.ByteString) (ResourceT IO) ())
  clientWithRoute pm _ req = do
    respStream <- runStreamingResponse <$> streamingRequest req
    let stream' = respStream responseBody
    return $ toStream stream'
    where
      toStream :: IO BS.ByteString -> Stream (Of BS.ByteString) (ResourceT IO) ()
      toStream read' = do
        bs <- liftIO read'
        liftIO $ print bs
        unless (BS.null bs) $ do
          S.yield bs
          toStream read'
