#!/bin/bash
set -euo pipefail

BINARY_PATH="${1:-}"

# The framework path the bridge hands to dlopen, and the notification the
# bridge subscribes to. Type names and the backend's display name also contain
# "MediaRemote", so a looser match would pass a binary whose bridge was cut out.
REQUIRED_STRINGS=(
    "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
)

if [ -z "$BINARY_PATH" ] || [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path-to-binary>"
    exit 1
fi

if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    exit 1
fi

BINARY_STRINGS=$(strings "$BINARY_PATH")

for required in "${REQUIRED_STRINGS[@]}"; do
    if ! grep -Fq -- "$required" <<<"$BINARY_STRINGS"; then
        echo "Error: '$required' not found in $BINARY_PATH — the MediaRemote bridge is not linked"
        exit 1
    fi
done

echo "MediaRemote Guard Passed: the MediaRemote bridge is linked into $BINARY_PATH"
