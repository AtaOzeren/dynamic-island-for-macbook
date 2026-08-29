#!/bin/bash
set -euo pipefail

DERIVED_DATA="${1:-$(mktemp -d)/DerivedData}"

build() {
    xcodebuild \
        -project NotchFlow.xcodeproj \
        -scheme "$1" \
        -configuration "$2" \
        -derivedDataPath "$DERIVED_DATA" \
        -destination "platform=macOS" \
        build >/dev/null
    "$DERIVED_DATA/Build/Products/$2/NotchFlow.app/Contents/MacOS/NotchFlow" --print-music-backend
}

APPSTORE_BACKEND=$(build "NotchFlow (App Store)" AppStore)
DIRECT_BACKEND=$(build "NotchFlow (Direct)" Direct)

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
