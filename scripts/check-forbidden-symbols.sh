#!/bin/bash
set -euo pipefail

BINARY_PATH="${1:-}"

if [ -z "$BINARY_PATH" ]; then
    echo "Usage: $0 <path-to-binary>"
    exit 1
fi

if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    exit 1
fi

FOUND=$(nm "$BINARY_PATH" 2>/dev/null | grep -Ei "MediaRemote|MRMediaRemote" || strings "$BINARY_PATH" | grep -Ei "MediaRemote|MRMediaRemote" || true)

if [ -n "$FOUND" ]; then
    echo "Error: Forbidden MediaRemote symbol or string found in App Store binary!"
    echo "$FOUND"
    exit 1
else
    echo "Forbidden Symbol Guard Passed: No MediaRemote symbols found in $BINARY_PATH"
    exit 0
fi
