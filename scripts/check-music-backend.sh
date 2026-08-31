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

if [ "$APPSTORE_BACKEND" != "ScriptingBridge" ]; then
    echo "Music Backend Guard Failure: AppStore must use ScriptingBridge, got '$APPSTORE_BACKEND'."
    exit 1
fi

OS_VERSION=$(sw_vers -productVersion)
OS_MAJOR=${OS_VERSION%%.*}
OS_REMAINDER=${OS_VERSION#*.}
OS_MINOR=${OS_REMAINDER%%.*}

if [ "$OS_MAJOR" -gt 15 ] || { [ "$OS_MAJOR" -eq 15 ] && [ "$OS_MINOR" -ge 4 ]; }; then
    DIRECT_EXPECTED="ScriptingBridge"
else
    DIRECT_EXPECTED="MediaRemote"
fi

if [ "$DIRECT_BACKEND" != "$DIRECT_EXPECTED" ]; then
    echo "Music Backend Guard Failure: Direct must use $DIRECT_EXPECTED on macOS $OS_VERSION, got '$DIRECT_BACKEND'."
    exit 1
fi

echo "Music Backend Guard Passed: both configurations match platform capabilities."
