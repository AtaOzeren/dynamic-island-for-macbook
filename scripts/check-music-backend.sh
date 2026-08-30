#!/bin/bash
set -euo pipefail

REPOSITORY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DERIVED_DATA="$REPOSITORY_ROOT/DerivedData/MusicBackendGuard"
FORCE=false

if [ "${1:-}" = "--force" ]; then
    FORCE=true
    shift
fi

if [ "$#" -ne 0 ]; then
    echo "Usage: $0 [--force]" >&2
    exit 2
fi

cd "$REPOSITORY_ROOT"

product() {
    echo "$DERIVED_DATA/Build/Products/$1/NotchFlow.app/Contents/MacOS/NotchFlow"
}

APPSTORE_PRODUCT=$(product AppStore)
DIRECT_PRODUCT=$(product Direct)

build() {
    xcodebuild \
        -project NotchFlow.xcodeproj \
        -scheme "$1" \
        -configuration "$2" \
        -derivedDataPath "$DERIVED_DATA" \
        -destination "generic/platform=macOS" \
        -quiet \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        build
}

if [ "$FORCE" = true ] || [ ! -x "$APPSTORE_PRODUCT" ] || [ ! -x "$DIRECT_PRODUCT" ]; then
    build "NotchFlow (App Store)" AppStore
    build "NotchFlow (Direct)" Direct
fi

APPSTORE_BACKEND=$("$APPSTORE_PRODUCT" --print-music-backend)
DIRECT_BACKEND=$("$DIRECT_PRODUCT" --print-music-backend)

echo "AppStore backend: $APPSTORE_BACKEND"
echo "Direct backend:   $DIRECT_BACKEND"

if [ "$APPSTORE_BACKEND" = "$DIRECT_BACKEND" ]; then
    echo "Music Backend Guard Failure: both configurations report '$APPSTORE_BACKEND'."
    exit 1
fi

if [ "$APPSTORE_BACKEND" != "ScriptingBridge" ]; then
    echo "Music Backend Guard Failure: AppStore must use ScriptingBridge, got '$APPSTORE_BACKEND'."
    exit 1
fi

if [ "$DIRECT_BACKEND" != "MediaRemote" ]; then
    echo "Music Backend Guard Failure: Direct must use MediaRemote, got '$DIRECT_BACKEND'."
    exit 1
fi

echo "Music Backend Guard Passed: each configuration selects its own backend."
