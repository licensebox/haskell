import Licensebox
import Control.Exception
import Control.Monad
import qualified Data.Map.Strict as M
import qualified Data.Aeson
main=do
 replicateM_ 100 $ do c<-create (Options "demo" (M.singleton "test-key" "A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg") "" Nothing (Just "/tmp/licensebox-haskell-lifetime") Nothing) defaultCallbacks;close c;r<-try (status c)::IO (Either LicenseboxError Data.Aeson.Value);case r of Left _->pure ();Right _->error "closed client accepted"

 c<-create (Options "demo" (M.singleton "test-key" "A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg") "" (Just "http://127.0.0.1:1") (Just "/tmp/licensebox-haskell-callback") Nothing) (defaultCallbacks {machineBinding=Just (throwIO (userError "expected callback failure"))})
 r<-try (signIn c 0.1)::IO (Either SomeException Data.Aeson.Value)
 close c
 case r of Left _->pure ();Right _->error "callback failure ignored"
