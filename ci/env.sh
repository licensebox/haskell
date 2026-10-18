#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${LICENSEBOX_LIBRARY:-}" && "$LICENSEBOX_LIBRARY" == */* ]]; then
 export LICENSEBOX_LIB_DIR="${LICENSEBOX_LIB_DIR:-$(dirname "$LICENSEBOX_LIBRARY")}"
fi
if [[ -z "${LICENSEBOX_LIB_DIR:-}" ]]; then
 if [[ -d ../c/build-shared ]]; then export LICENSEBOX_LIB_DIR="$(cd ../c/build-shared && pwd)"
 else export LICENSEBOX_LIB_DIR="$(cd ../native/lib && pwd)"; fi
fi
if [[ -z "${LICENSEBOX_INCLUDE_DIR:-}" ]]; then
 if [[ -d "$LICENSEBOX_LIB_DIR/../include" ]]; then export LICENSEBOX_INCLUDE_DIR="$(cd "$LICENSEBOX_LIB_DIR/../include" && pwd)"
 elif [[ -d ../native-src/include ]]; then export LICENSEBOX_INCLUDE_DIR="$(cd ../native-src/include && pwd)"
 else export LICENSEBOX_INCLUDE_DIR="$(cd ../c/include && pwd)"; fi
fi
export LD_LIBRARY_PATH="$LICENSEBOX_LIB_DIR:${LD_LIBRARY_PATH:-}"
export LICENSEBOX_LIBRARY="${LICENSEBOX_LIBRARY:-$LICENSEBOX_LIB_DIR/liblicensebox.so}"
mkdir -p build
