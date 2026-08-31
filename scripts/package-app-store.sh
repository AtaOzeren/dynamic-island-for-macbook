#!/bin/bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT_DIR=${OUTPUT_DIR:-"$PROJECT_ROOT/dist/app-store"}
DERIVED_DATA_PATH=${DERIVED_DATA_PATH:-"$PROJECT_ROOT/DerivedData/AppStoreSubmission"}
ARCHIVE_PATH="$OUTPUT_DIR/NotchFlow.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/NotchFlow.app"
APP_BINARY="$APP_PATH/Contents/MacOS/NotchFlow"
APPLE_TEAM_ID=${APPLE_TEAM_ID:-}
ASSET_CHECK_PATH=${ASSET_CHECK_PATH:-"$PROJECT_ROOT/scripts/check-assets.sh"}
FORBIDDEN_SYMBOL_CHECK_PATH=${FORBIDDEN_SYMBOL_CHECK_PATH:-"$PROJECT_ROOT/scripts/check-forbidden-symbols.sh"}

rm -rf "$DERIVED_DATA_PATH" "$ARCHIVE_PATH"
mkdir -p "$OUTPUT_DIR"

echo "==> Archiving NotchFlow (App Store)"
ARCHIVE_ARGUMENTS=(
    -project "$PROJECT_ROOT/NotchFlow.xcodeproj"
    -scheme "NotchFlow (App Store)"
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
    echo "Error: archive did not contain NotchFlow.app" >&2
    exit 1
fi

echo "==> Running local App Store validation"
plutil -lint \
    "$APP_PATH/Contents/Info.plist" \
    "$PROJECT_ROOT/NotchFlow-AppStore.entitlements" \
    "$PROJECT_ROOT/AppStore-ExportOptions.plist"
"$ASSET_CHECK_PATH"
"$FORBIDDEN_SYMBOL_CHECK_PATH" "$APP_BINARY"

ARCHIVED_BUNDLE_ID=$(defaults read "$APP_PATH/Contents/Info" CFBundleIdentifier)
if [ "$ARCHIVED_BUNDLE_ID" != "com.notchflow.NotchFlow" ]; then
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

echo "App Store archive: $ARCHIVE_PATH"
echo "Local validation completed with zero errors."
