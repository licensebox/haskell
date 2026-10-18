# Validation — 2026-10-18

PASS: GHC 9.4.7 + aeson 2.1 actual FFI compilation, repeated creation/close, callback exception containment, and all 69 shared protocol checks. Cabal packaging/install checks are supplied for CI; no local cabal executable was available.

The C core was built as a shared library from the public SDK checkout. Test keys, times, identities and loopback server data are synthetic. Linux x86-64 only; other OS/runtime paths are unvalidated. No remote release or registry publication is performed by these scripts.
