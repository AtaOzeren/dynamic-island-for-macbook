#!/bin/bash
set -euo pipefail

CORE_DIR="${1:-Sources/NotchFlowCore}"

if [ ! -d "$CORE_DIR" ]; then
    echo "Error: Directory $CORE_DIR does not exist."
    exit 1
fi

VIOLATIONS=$(grep -Er 'import[[:space:]]+(AppKit|SwiftUI|NotchFlowProviders|NotchFlowUI)' "$CORE_DIR" || true)

if [ -n "$VIOLATIONS" ]; then
    echo "Architecture Guard Failure: Forbidden import found in NotchFlowCore:"
    echo "$VIOLATIONS"
    exit 1
else
    echo "Architecture Guard Passed: NotchFlowCore has clean dependencies."
    exit 0
fi
