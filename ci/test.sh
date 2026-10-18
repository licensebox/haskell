#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source ci/env.sh
# aeson is installed by apt for this exact compiler/package database, rather
# than the independently preinstalled ghcup compiler earlier on runner PATH.
ghc=/usr/bin/ghc
cabal=/usr/bin/cabal
"$ghc" --version
/usr/bin/ghc-pkg latest aeson
for target in Adapter Lifetime; do
 mkdir -p "build/$target"
 "$ghc" -threaded -isrc -package aeson -L"$LICENSEBOX_LIB_DIR" -llicensebox -outputdir "build/$target" "test/$target.hs" -o "build/${target,,}"
done
build/lifetime
"$cabal" check
# Resolve against the apt-installed packages without secure-repository bootstrap
# or downloads on a fresh runner, even when no Hackage index has been cached.
cat > build/cabal.project <<'PROJECT'
packages: ..
active-repositories: :none
PROJECT
# Cabal 3.8 still initializes repositories from its default global config before
# applying project policy. Supply a config with no repository declarations at all.
cat > build/cabal.config <<CONFIG
remote-repo-cache: $PWD/build/cabal-repositories
store-dir: $PWD/build/cabal-store
CONFIG
"$cabal" --config-file="$PWD/build/cabal.config" v2-build --offline --project-file="$PWD/build/cabal.project" --builddir="$PWD/build/cabal"  --with-compiler="$ghc" --with-hc-pkg=/usr/bin/ghc-pkg --extra-lib-dirs="$LICENSEBOX_LIB_DIR" all
"$cabal" --config-file="$PWD/build/cabal.config" sdist --project-file="$PWD/build/cabal.project" --output-directory "$PWD/build"
