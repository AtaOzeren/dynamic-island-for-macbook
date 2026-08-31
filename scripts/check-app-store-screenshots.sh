#!/bin/bash
set -euo pipefail

SCREENSHOT_DIR=${1:-"docs/store/screenshots/en-US"}

python3 - "$SCREENSHOT_DIR" <<'PYTHON'
import pathlib
import struct
import sys

directory = pathlib.Path(sys.argv[1])
expected_names = {
    "01-music.png",
    "02-timer.png",
    "03-ai-agent.png",
    "04-recording.png",
    "05-settings.png",
}
allowed_sizes = {(1280, 800), (1440, 900), (2560, 1600), (2880, 1800)}
failures = []

actual_names = {path.name for path in directory.glob("*.png")} if directory.is_dir() else set()
for missing_name in sorted(expected_names - actual_names):
    failures.append(f"missing {missing_name}")
for unexpected_name in sorted(actual_names - expected_names):
    failures.append(f"unexpected {unexpected_name}")

for name in sorted(expected_names & actual_names):
    path = directory / name
    header = path.read_bytes()[:26]
    if len(header) < 26 or header[:8] != b"\x89PNG\r\n\x1a\n":
        failures.append(f"{name}: not a PNG")
        continue
    width, height = struct.unpack(">II", header[16:24])
    color_type = header[25]
    if (width, height) not in allowed_sizes:
        failures.append(f"{name}: unsupported size {width}x{height}")
    if color_type in {4, 6}:
        failures.append(f"{name}: alpha channel is not allowed")

if failures:
    print("App Store screenshot validation failed:", file=sys.stderr)
    for failure in failures:
        print(f"- {failure}", file=sys.stderr)
    raise SystemExit(1)

print(f"App Store screenshot validation passed: {len(expected_names)} images are upload-ready.")
PYTHON
