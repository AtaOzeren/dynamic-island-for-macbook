#!/bin/bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT_DIR=${OUTPUT_DIR:-"$PROJECT_ROOT/dist/app-store"}
# Spotlight skips any path whose component ends in `.noindex`, so the app
# bundles a packaging run produces never surface beside the installed app in
# Spotlight and Launchpad. Every stray "KerNotch.app" a user finds there is a
# build product, and each one is a copy they can launch by mistake.
DERIVED_DATA_PATH=${DERIVED_DATA_PATH:-"$PROJECT_ROOT/DerivedData.noindex/AppStoreSubmission"}
ARCHIVE_PATH="$OUTPUT_DIR/KerNotch.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/KerNotch.app"
APP_BINARY="$APP_PATH/Contents/MacOS/KerNotch"
APPLE_TEAM_ID=${APPLE_TEAM_ID:-}
ASSET_CHECK_PATH=${ASSET_CHECK_PATH:-"$PROJECT_ROOT/scripts/check-assets.sh"}
FORBIDDEN_SYMBOL_CHECK_PATH=${FORBIDDEN_SYMBOL_CHECK_PATH:-"$PROJECT_ROOT/scripts/check-forbidden-symbols.sh"}

# xcodebuild registers every product it builds with LaunchServices, which is
# how a packaging run leaves a second "KerNotch.app" in Spotlight and
# Launchpad beside the one the user installed — a copy they can launch by
# mistake, and one that never updates again. The `.noindex` derived-data path
# keeps Spotlight out; LaunchServices ignores that convention, so the
# registration is withdrawn here instead. Best effort: a packaged artefact is
# the point of the run, and a stale registration must not fail it.
unregister_from_launch_services() {
    local lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
    [ -x "$lsregister" ] || return 0
    local bundle
    for bundle in "$@"; do
        [ -e "$bundle" ] || continue
        "$lsregister" -u "$bundle" >/dev/null 2>&1 || true
    done
}

rm -rf "$DERIVED_DATA_PATH" "$ARCHIVE_PATH"
mkdir -p "$OUTPUT_DIR"

echo "==> Archiving KerNotch (App Store)"
ARCHIVE_ARGUMENTS=(
    -project "$PROJECT_ROOT/KerNotch.xcodeproj"
    -scheme "KerNotch (App Store)"
    -configuration AppStore
    -destination "generic/platform=macOS"
    -derivedDataPath "$DERIVED_DATA_PATH"
    -archivePath "$ARCHIVE_PATH"
)

if [ -n "$APPLE_TEAM_ID" ]; then
    xcodebuild "${ARCHIVE_ARGUMENTS[@]}" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" -allowProvisioningUpdates archive
else
    xcodebuild "${ARCHIVE_ARGUMENTS[@]}" CODE_SIGNING_ALLOWED=NO archive
fi

if [ ! -d "$APP_PATH" ] || [ ! -f "$APP_BINARY" ]; then
    echo "Error: archive did not contain KerNotch.app" >&2
    exit 1
fi

echo "==> Running local App Store validation"
plutil -lint \
    "$APP_PATH/Contents/Info.plist" \
    "$PROJECT_ROOT/KerNotch-AppStore.entitlements" \
    "$PROJECT_ROOT/AppStore-ExportOptions.plist"
"$ASSET_CHECK_PATH"
"$FORBIDDEN_SYMBOL_CHECK_PATH" "$APP_BINARY"

ARCHIVED_BUNDLE_ID=$(defaults read "$APP_PATH/Contents/Info" CFBundleIdentifier)
if [ "$ARCHIVED_BUNDLE_ID" != "com.kernotch.KerNotch" ]; then
    echo "Error: unexpected archived bundle identifier: $ARCHIVED_BUNDLE_ID" >&2
    exit 1
fi

if [ -n "$APPLE_TEAM_ID" ]; then
    echo "==> Verifying distribution signature"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    spctl --assess --type execute --verbose=2 "$APP_PATH"
    echo "Signed archive is ready for Organizer validation and App Store Connect upload."
else
    echo "SKIPPED (no membership): distribution signing and provisioning"
    echo "SKIPPED (no membership): Organizer/App Store Connect validation"
    echo "Set APPLE_TEAM_ID after enrollment to produce and validate a distribution-signed archive."
fi

unregister_from_launch_services "$APP_PATH"

echo "App Store archive: $ARCHIVE_PATH"
echo "Local validation completed with zero errors."
