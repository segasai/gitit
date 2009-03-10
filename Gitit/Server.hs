{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
{-
Copyright (C) 2008 John MacFarlane <jgm@berkeley.edu>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{- Re-exports HAppS functions needed by gitit, including 
   replacements for HAppS functions that don't handle UTF-8 properly, and
   new functions for setting headers and zipping contents and for looking up IP
   addresses.
-}

module Gitit.Server
          ( look
          , lookPairs
          , lookRead
          , mkCookie
          , withExpiresHeaders
          , setContentType
          , setFilename
          , lookupIPAddr
          , readMimeTypesFile
          -- re-exported HAppS functions
          , ok
          , toResponse
          , Response(..)
          , Method(..)
          , Request(..)
          , Input(..)
          , HeaderPair(..)
          , Web
          , ServerPart
          , FromData(..)
          , waitForTermination
          , Conf(..)
          , simpleHTTP
          , fileServe
          , dir
          , multi
          , seeOther
          , withData
          , withRequest
          , anyRequest
          , noHandle
          , uriRest
          , lookInput
          , addCookie
          , lookCookieValue
          , readCookieValue
          )
where
import Happstack.Server hiding (look, lookRead, lookPairs, mkCookie, getCookies)
import qualified Happstack.Server (mkCookie)
import Happstack.Server.Cookie (Cookie(..))
import Network.Socket (getAddrInfo, defaultHints, addrAddress)
import System.IO (stderr, hPutStrLn)
import Text.Pandoc.CharacterReferences (decodeCharacterReferences)
import Control.Monad.Reader
import Data.ByteString.Lazy.UTF8 (toString)
import Codec.Binary.UTF8.String (encodeString)
import Data.Maybe
import qualified Data.Map as M

-- Contents of an HTML text area or text field generated by Text.XHtml
-- will often contain decimal character references.  We want to convert these
-- to regular unicode characters.  We also need to use toString to
-- convert from UTF-8, since HAppS doesn't do this.

look :: String -> RqData String
look = liftM (decodeCharacterReferences . toString) . lookBS

lookPairs :: RqData [(String,String)]
lookPairs = asks fst >>= return . map (\(n,vbs)->(n,toString $ inputValue vbs))

lookRead :: Read a => String -> RqData a
lookRead = liftM read . look

mkCookie :: String -> String -> Cookie
mkCookie name = Happstack.Server.mkCookie name . encodeString

withExpiresHeaders :: ServerPart Response -> ServerPart Response
withExpiresHeaders = liftM (setHeader "Cache-Control" "max-age=21600")

setContentType :: String -> Response -> Response
setContentType = setHeader "Content-Type"

setFilename :: String -> Response -> Response
setFilename = setHeader "Content-Disposition" . \fname -> "attachment: filename=\"" ++ fname ++ "\""

-- IP lookup

lookupIPAddr :: String -> IO (Maybe String)
lookupIPAddr hostname = do
  addrs <- getAddrInfo (Just defaultHints) (Just hostname) Nothing
  if null addrs
     then return Nothing
     else return $ Just $ takeWhile (/=':') $ show $ addrAddress $ head addrs


-- mime types

-- | Read a file associating mime types with extensions, and return a
-- map from extensions to types. Each line of the file consists of a
-- mime type, followed by space, followed by a list of zero or more
-- extensions, separated by spaces. Example: text/plain txt text
readMimeTypesFile :: FilePath -> IO (M.Map String String)
readMimeTypesFile f = catch (readFile f >>= return . foldr go M.empty . map words . lines) $
                            handleMimeTypesFileNotFound
     where go []     m = m  -- skip blank lines
           go (x:xs) m = foldr (\ext m' -> M.insert ext x m') m xs
           handleMimeTypesFileNotFound e = do
             hPutStrLn stderr $ "Could not read mime types file: " ++ f
             hPutStrLn stderr $ show e
             hPutStrLn stderr $ "Using defaults instead."
             return mimeTypes

-- Note: waitForTermination is copied from Happstack.State.Control
-- to avoid a dependency on happstack-state.   (Shouldn't this
-- function be in happstack-server?)

-- | Wait for a signal.
--   On unix, a signal is sigINT or sigTERM. On windows, the signal
--   is entering 'e'.
waitForTermination :: IO ()
waitForTermination
    = do
#ifdef UNIX
         istty <- queryTerminal stdInput
         mv <- newEmptyMVar
         installHandler softwareTermination (CatchOnce (putMVar mv ())) Nothing
         case istty of
           True  -> do installHandler keyboardSignal (CatchOnce (putMVar mv ())) Nothing
                       return ()
           False -> return ()
         takeMVar mv
#else
         let loop 'e' = return () 
             loop _   = getChar >>= loop
         loop 'c'
#endif

