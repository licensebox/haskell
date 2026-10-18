{-# LANGUAGE ForeignFunctionInterface, OverloadedStrings, DeriveDataTypeable #-}
module Licensebox (Client,Options(..),Callbacks(..),defaultCallbacks,LicenseboxError(..),create,close,withClient,lease,heartbeat,require,status,signIn,logout,modules,requests,requestAccess,accessLink,record,deriveBinding,nativeBinding,verifyLease) where
import Prelude hiding (read,product)
import Control.Concurrent.MVar
import Control.Exception
import Control.Monad
import Data.Aeson hiding (json,Options)
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import qualified Data.Map.Strict as M
import Data.IORef
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as E
import Data.Typeable
import Foreign
import Foreign.C
import qualified Foreign.Concurrent as FC

data LicenseboxError=LicenseboxError {errorCode::String} deriving (Show,Typeable)
instance Exception LicenseboxError
data Callbacks=Callbacks {onSignIn::Maybe (String->String->IO ()),clock::Maybe (IO Double),machineBinding::Maybe (IO String),cancelled::Maybe (IO Bool)}
defaultCallbacks=Callbacks Nothing Nothing Nothing Nothing
data Options=Options {product::String,keys::M.Map String String,version::String,server::Maybe String,directory::Maybe String,caBundle::Maybe String}
data Client=Client (ForeignPtr ()) (MVar ()) (IORef (Ptr ())) (IORef Bool) (IORef (Maybe SomeException))
foreign import ccall safe "lb_client_create_json" c_create::CString->Ptr ()->Ptr (Ptr ())->IO CInt
foreign import ccall safe "lb_client_call_json" c_call::Ptr ()->CString->CString->Ptr CString->IO CInt
foreign import ccall unsafe "lb_client_destroy" c_destroy::Ptr ()->IO ()
foreign import ccall unsafe "lb_free" c_free::Ptr a->IO ()
foreign import ccall unsafe "lb_result_code" c_code::CInt->IO CString
foreign import ccall unsafe "lb_error_code" c_error::Ptr ()->IO CString
foreign import ccall unsafe "lb_derive_binding" c_derive::CString->CString->CString->CString->CSize->IO CInt
foreign import ccall unsafe "lb_native_binding" c_native::CString->CString->CSize->IO CInt
foreign import ccall unsafe "lb_verify_lease_json" c_verify::CString->CString->CString->CDouble->Ptr CString->IO CInt
foreign import ccall "wrapper" wrapSign::(Ptr ()->CString->CString->IO ())->IO (FunPtr (Ptr ()->CString->CString->IO ()))
foreign import ccall "wrapper" wrapClock::(Ptr ()->IO CDouble)->IO (FunPtr (Ptr ()->IO CDouble))
foreign import ccall "wrapper" wrapBinding::(Ptr ()->CString->CSize->IO CInt)->IO (FunPtr (Ptr ()->CString->CSize->IO CInt))
foreign import ccall "wrapper" wrapCancel::(Ptr ()->IO CInt)->IO (FunPtr (Ptr ()->IO CInt))
utf8 s action | '\0' `elem` s=throwIO (LicenseboxError "invalid_argument") | otherwise=B.useAsCString (E.encodeUtf8 (T.pack s)) action
peekUTF p=T.unpack . E.decodeUtf8 <$> B.packCString p
json v action=B.useAsCString (L.toStrict (encode v)) action
raise rc h=do p<-if h==nullPtr || rc==22 then c_code rc else c_error h;code<-peekCString p;if code=="ok" then c_code rc >>= peekCString >>= throwIO . LicenseboxError else throwIO (LicenseboxError code)
owned :: CInt -> Ptr () -> Ptr CString -> IO Value
owned rc h p=do out<-peek p;if rc/=0 then c_free out>>raise rc h else if out==nullPtr then throwIO (LicenseboxError "protocol_error") else bracket (pure out) c_free $ \x->do raw<-B.packCString x;either (const $ throwIO $ LicenseboxError "protocol_error") pure (eitherDecodeStrict' raw)
create o callbacks=mask $ \restore->do
 gate<-newMVar ();ptr<-newIORef nullPtr;inCallback<-newIORef False;failure<-newIORef Nothing
 let guardCallback fallback act=(bracket_ (writeIORef inCallback True) (writeIORef inCallback False) act) `catch` \e->writeIORef failure (Just e)>>pure fallback
 sign<-case onSignIn callbacks of Nothing->pure nullFunPtr;Just f->wrapSign $ \_ u c->guardCallback () (peekUTF u >>= \a->peekUTF c >>= f a)
 clk<-case clock callbacks of Nothing->pure nullFunPtr;Just f->wrapClock $ \_->guardCallback 0 $ do n<-f;if isNaN n||isInfinite n then throwIO (LicenseboxError "invalid_argument") else pure (realToFrac n)
 bind<-case machineBinding callbacks of Nothing->pure nullFunPtr;Just f->wrapBinding $ \_ out cap->guardCallback 1 $ do s<-f;utf8 s $ \p->do n<-B.length . E.encodeUtf8 . T.pack <$> pure s;if n>=fromIntegral cap then throwIO (LicenseboxError "invalid_argument") else copyBytes out p (n+1)>>pure 0
 cancel<-wrapCancel $ \_->guardCallback 1 $ do failed<-readIORef failure;case failed of Just _->pure 1;Nothing->maybe (pure 0) (fmap (\b->if b then 1 else 0)) (cancelled callbacks)
 let callbacksFree=mapM_ freeHaskellFunPtr $ filter (/=nullFunPtr) [castFunPtr sign,castFunPtr clk,castFunPtr bind,castFunPtr cancel]
 let values=["product".=product o,"keys".=keys o,"version".=version o] ++ maybe [] (\x->["server".=x]) (server o) ++ maybe [] (\x->["directory".=x]) (directory o) ++ maybe [] (\x->["ca_bundle".=x]) (caBundle o)
 h<- (allocaBytes (5*sizeOf (nullPtr::Ptr ())) $ \cb->do
   let pointers=[nullPtr,castFunPtrToPtr sign,castFunPtrToPtr clk,castFunPtrToPtr bind,castFunPtrToPtr cancel]
   sequence_ [pokeByteOff cb (i*sizeOf (nullPtr::Ptr ())) p | (i,p)<-zip [0..] pointers]
   alloca $ \out->do poke out nullPtr;rc<-restore $ json (object values) $ \s->c_create s cb out;h<-peek out;failed<-readIORef failure;case failed of Just e->c_destroy h>>throwIO e;Nothing->if rc/=0 then c_destroy h>>raise rc nullPtr else pure h) `onException` callbacksFree
 writeIORef ptr h
 fp<-FC.newForeignPtr h (withMVar gate $ \_->do p<-atomicModifyIORef' ptr (\x->(nullPtr,x));when (p/=nullPtr) (c_destroy p);callbacksFree)
 pure (Client fp gate ptr inCallback failure)
close (Client fp gate ptr inCallback _)=do cb<-readIORef inCallback;when cb (throwIO $ LicenseboxError "invalid_argument");withMVar gate $ \_->do p<-atomicModifyIORef' ptr (\x->(nullPtr,x));when (p/=nullPtr) (c_destroy p);touchForeignPtr fp
withClient o cb=bracket (create o cb) close
call :: Client -> String -> Value -> IO Value
call (Client fp gate ptr inCallback failure) op args=do
 cb<-readIORef inCallback;when cb (throwIO $ LicenseboxError "invalid_argument")
 withMVar gate $ \_->withForeignPtr fp $ \_->do
  h<-readIORef ptr;when (h==nullPtr) (throwIO $ LicenseboxError "closed")
  mask_ $ alloca $ \out->do poke out nullPtr;rc<-utf8 op $ \o->json args $ \a->c_call h o a out;failed<-atomicModifyIORef' failure (\x->(Nothing,x));case failed of Just e->peek out >>= c_free >> throwIO e;Nothing->owned rc h out
lease c=call c "lease" (object [])
heartbeat :: Client -> String -> IO Value
heartbeat c moduleName=call c "heartbeat" (object ["module".=moduleName])
require c m=call c "require" (object ["module".=(m::String)])
status c=call c "status" (object [])
signIn c t=call c "sign_in" (object ["timeout".=(t::Double)])
logout c=call c "logout" (object [])
modules c=call c "modules" (object [])
requests c=call c "requests" (object [])
requestAccess c ms note=call c "request" (object ["modules".=(ms::[String]),"note".=(note::String)])
accessLink c=call c "access-link" (object [])
record c cmd ok elapsed=call c "record" (object ["command".=(cmd::String),"success".=(ok::Bool),"elapsed".=(elapsed::Double)])
deriveBinding p s raw=allocaBytes 128 $ \out->do rc<-utf8 p $ \p'->utf8 s $ \s'->utf8 (reverse $ dropWhile (=='\0') $ reverse raw) $ \r->c_derive p' s' r out 128;if rc/=0 then raise rc nullPtr else peekUTF out
nativeBinding p=allocaBytes 128 $ \out->do rc<-utf8 p $ \p'->c_native p' out 128;if rc/=0 then raise rc nullPtr else peekUTF out
verifyLease t p k now=alloca $ \out->do poke out nullPtr;rc<-utf8 t $ \t'->utf8 p $ \p'->json (k::M.Map String String) $ \k'->c_verify t' p' k' (realToFrac (now::Double)) out;owned rc nullPtr out
