{-# LANGUAGE OverloadedStrings #-}
import Licensebox
import Control.Exception
import Data.Aeson
import Data.Aeson.Types
import qualified Data.ByteString.Lazy.Char8 as B
import qualified Data.Aeson.KeyMap as K
import qualified Data.Aeson.Key as Key
import qualified Data.Map.Strict as M
import Data.String (fromString)
get :: FromJSON a => Object -> String -> a
get o k=case parseEither (.: Key.fromString k) o of Right x->x;Left e->error e
optional :: FromJSON a => Object -> String -> Maybe a
optional o k=case K.lookup (Key.fromString k) o of Nothing->Nothing;Just v->case fromJSON v of Success x->Just x;Error _->Nothing
run r=do
 let op=get r "op"::String;p=get r "product";ks=get r "keys";now=get r "now"
 case op of
  "derive"->String . fromString <$> deriveBinding p (get r "source") (get r "raw_id")
  "native"->String . fromString <$> nativeBinding p
  "verify"->verifyLease (get r "token") p ks now
  _->withClient (Options p ks "conformance" (Just $ get r "server") (Just $ get r "directory") (optional r "ca_bundle")) (defaultCallbacks {clock=Just (pure now),machineBinding=Just (pure $ maybe "" id $ optional r "binding"),onSignIn=Just (\_ _->pure ())}) $ \c->case op of
   "lease"->lease c
   "require"->require c (maybe "core" id $ optional r "module")
   "repeat"->require c "core">>require c "core"
   "status"->status c
   "sign_in"->signIn c 3
   "logout"->logout c
   "modules"->modules c
   "requests"->requests c
   "request"->requestAccess c ["export"] "café – test"
   "access-link"->accessLink c
   "record"->record c "export" True 0.125>>record c "export" False 0.025>>pure Null
   _->error "unknown operation"
main=do raw<-B.getContents;let Right (Object r)=eitherDecode raw
        answer<-((\v->object ["ok".=True,"value".=v]) <$> run r) `catch` \(LicenseboxError code)->pure (object ["ok".=False,"error".=code])
        B.putStrLn (encode answer)
