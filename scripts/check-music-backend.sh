#!/bin/bash
set -euo pipefail

REPOSITORY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DERIVED_DATA="$REPOSITORY_ROOT/DerivedData/MusicBackendGuard"
PRODUCT="$DERIVED_DATA/Build/Products/Release/KerNotch.app/Contents/MacOS/KerNotch"
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

if [ "$FORCE" = true ] || [ ! -x "$PRODUCT" ]; then
    xcodebuild \
        -project KerNotch.xcodeproj \
        -scheme KerNotch \
        -configuration Release \
        -derivedDataPath "$DERIVED_DATA" \
        -destination "generic/platform=macOS" \
        -quiet \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        build
fi

BACKEND=$("$PRODUCT" --print-music-backend)
echo "Music backend: $BACKEND"

OS_VERSION=$(sw_vers -productVersion)
OS_MAJOR=${OS_VERSION%%.*}
OS_REMAINDER=${OS_VERSION#*.}
OS_MINOR=${OS_REMAINDER%%.*}

# macOS 15.4 restricted MediaRemote metadata to Apple-signed processes, so
# newer systems fall back to scripting Spotify and Apple Music directly.
if [ "$OS_MAJOR" -gt 15 ] || { [ "$OS_MAJOR" -eq 15 ] && [ "$OS_MINOR" -ge 4 ]; }; then
    EXPECTED="ScriptingBridge"
else
    EXPECTED="MediaRemote"
fi

if [ "$BACKEND" != "$EXPECTED" ]; then
    echo "Music Backend Guard Failure: expected $EXPECTED on macOS $OS_VERSION, got '$BACKEND'."
    exit 1
fi

echo "Music Backend Guard Passed: the backend matches macOS $OS_VERSION."
