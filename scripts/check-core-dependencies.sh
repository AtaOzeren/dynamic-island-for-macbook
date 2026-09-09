#!/bin/bash
set -euo pipefail

CORE_DIR="${1:-Sources/KerNotchCore}"

if [ ! -d "$CORE_DIR" ]; then
    echo "Error: Directory $CORE_DIR does not exist."
    exit 1
fi

VIOLATIONS=$(grep -Er 'import[[:space:]]+(AppKit|SwiftUI|KerNotchProviders|KerNotchUI)' "$CORE_DIR" || true)

if [ -n "$VIOLATIONS" ]; then
    echo "Architecture Guard Failure: Forbidden import found in KerNotchCore:"
    echo "$VIOLATIONS"
    exit 1
else
    echo "Architecture Guard Passed: KerNotchCore has clean dependencies."
    exit 0
fi
