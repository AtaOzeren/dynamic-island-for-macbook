#!/bin/bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT_DIR=${OUTPUT_DIR:-"$PROJECT_ROOT/dist"}
DERIVED_DATA_PATH=${DERIVED_DATA_PATH:-"$PROJECT_ROOT/DerivedData/DirectPackage"}
PACKAGE_STAGE_PATH=${PACKAGE_STAGE_PATH:-"$DERIVED_DATA_PATH/PackageStage"}
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Direct/NotchFlow.app"
ENTITLEMENTS_PATH="$PROJECT_ROOT/NotchFlow-Direct.entitlements"
DEVELOPER_ID_APPLICATION=${DEVELOPER_ID_APPLICATION:-}
NOTARYTOOL_KEYCHAIN_PROFILE=${NOTARYTOOL_KEYCHAIN_PROFILE:-}
NOTARYTOOL_KEYCHAIN=${NOTARYTOOL_KEYCHAIN:-}

if { [ -n "$DEVELOPER_ID_APPLICATION" ] && [ -z "$NOTARYTOOL_KEYCHAIN_PROFILE" ]; } || \
    { [ -z "$DEVELOPER_ID_APPLICATION" ] && [ -n "$NOTARYTOOL_KEYCHAIN_PROFILE" ]; }; then
    echo "Error: DEVELOPER_ID_APPLICATION and NOTARYTOOL_KEYCHAIN_PROFILE must be set together" >&2
    exit 1
fi

rm -rf "$DERIVED_DATA_PATH" "$PACKAGE_STAGE_PATH"
mkdir -p "$OUTPUT_DIR"

echo "==> Building NotchFlow (Direct)"
xcodebuild \
    -project "$PROJECT_ROOT/NotchFlow.xcodeproj" \
    -scheme "NotchFlow (Direct)" \
    -configuration Direct \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Built app not found at $APP_PATH" >&2
    exit 1
fi

if [ -n "$DEVELOPER_ID_APPLICATION" ]; then
    if ! security find-identity -v -p codesigning | grep -Fq "\"$DEVELOPER_ID_APPLICATION\""; then
        echo "Error: Developer ID identity not found: $DEVELOPER_ID_APPLICATION" >&2
        exit 1
    fi

    echo "==> Signing with Developer ID"
    codesign \
        --force \
        --deep \
        --options runtime \
        --entitlements "$ENTITLEMENTS_PATH" \
        --timestamp \
        --sign "$DEVELOPER_ID_APPLICATION" \
        "$APP_PATH"
else
    echo "==> Signing ad-hoc with hardened runtime"
    codesign \
        --force \
        --deep \
        --options runtime \
        --entitlements "$ENTITLEMENTS_PATH" \
        --sign - \
        "$APP_PATH"
    echo "SKIPPED (no membership): Developer ID signing"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
if [ -z "$VERSION" ]; then
    echo "Error: CFBundleShortVersionString is missing from the built app" >&2
    exit 1
fi

if [ -n "$NOTARYTOOL_KEYCHAIN_PROFILE" ]; then
    NOTARYTOOL_ARGUMENTS=(--keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE")
    if [ -n "$NOTARYTOOL_KEYCHAIN" ]; then
        NOTARYTOOL_ARGUMENTS+=(--keychain "$NOTARYTOOL_KEYCHAIN")
    fi
    APP_ARCHIVE="$DERIVED_DATA_PATH/NotchFlow.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$APP_ARCHIVE"
    echo "==> Notarizing app"
    xcrun notarytool submit \
        "$APP_ARCHIVE" \
        "${NOTARYTOOL_ARGUMENTS[@]}" \
        --wait
    echo "==> Stapling app"
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
else
    echo "SKIPPED: notarization"
    echo "SKIPPED: stapling"
fi

DISK_IMAGE="$OUTPUT_DIR/NotchFlow-$VERSION-direct.dmg"
rm -f "$DISK_IMAGE" "$DISK_IMAGE.sha256"
mkdir -p "$PACKAGE_STAGE_PATH"
ditto "$APP_PATH" "$PACKAGE_STAGE_PATH/NotchFlow.app"
ln -s /Applications "$PACKAGE_STAGE_PATH/Applications"

echo "==> Creating $DISK_IMAGE"
hdiutil create \
    -volname NotchFlow \
    -format UDZO \
    -srcfolder "$PACKAGE_STAGE_PATH" \
    -ov \
    "$DISK_IMAGE"

if [ -n "$NOTARYTOOL_KEYCHAIN_PROFILE" ]; then
    echo "==> Notarizing disk image"
    xcrun notarytool submit \
        "$DISK_IMAGE" \
        "${NOTARYTOOL_ARGUMENTS[@]}" \
        --wait
    echo "==> Stapling disk image"
    xcrun stapler staple "$DISK_IMAGE"
    xcrun stapler validate "$DISK_IMAGE"
fi

(
    cd "$OUTPUT_DIR"
    shasum -a 256 "$(basename "$DISK_IMAGE")" > "$(basename "$DISK_IMAGE").sha256"
)

echo "==> Packaged $DISK_IMAGE"
echo "==> Checksum $DISK_IMAGE.sha256"
