#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source ci/env.sh
for target in Adapter Lifetime; do
 mkdir -p "build/$target"
 ghc -threaded -isrc -package aeson -L"$LICENSEBOX_LIB_DIR" -llicensebox -outputdir "build/$target" "test/$target.hs" -o "build/${target,,}"
done
build/lifetime
cabal check
cabal v2-build --offline --extra-lib-dirs="$LICENSEBOX_LIB_DIR" all
cabal sdist --output-directory build
