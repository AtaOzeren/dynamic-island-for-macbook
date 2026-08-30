#!/bin/bash
set -euo pipefail

# The asset catalog never fails loudly for a missing icon: `actool` substitutes
# a blank slot and ships, so a dropped size surfaces as an empty Dock tile after
# release rather than as a red build. This asserts every size the catalog
# promises is present, is a real PNG, and is exactly the pixel dimensions its
# size-and-scale pair implies.
CATALOG="NotchFlow/Assets.xcassets"

python3 - "$CATALOG" <<'PYTHON'
import json
import pathlib
import struct
import sys

catalog = pathlib.Path(sys.argv[1])
failures = []


def png_pixel_size(path):
    header = path.read_bytes()[:24]
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    return struct.unpack(">II", header[16:24])


def check(image_set, expected_for):
    contents = image_set / "Contents.json"
    if not contents.is_file():
        failures.append(f"{image_set.name}: no Contents.json")
        return

    manifest = json.loads(contents.read_text(encoding="utf-8"))
    entries = manifest.get("images", [])
    if not entries:
        failures.append(f"{image_set.name}: declares no images")

    for entry in entries:
        filename = entry.get("filename")
        if filename is None:
            failures.append(f"{image_set.name}: an entry declares no filename")
            continue

        image = image_set / filename
        if not image.is_file():
            failures.append(f"{image_set.name}/{filename}: declared but missing")
            continue

        try:
            width, height = png_pixel_size(image)
        except ValueError as error:
            failures.append(f"{image_set.name}/{filename}: {error}")
            continue

        expected = expected_for(entry)
        if expected is None:
            continue
        if (width, height) != (expected, expected):
            failures.append(
                f"{image_set.name}/{filename}: is {width}x{height}, "
                f"expected {expected}x{expected}"
            )


def app_icon_pixels(entry):
    points = int(entry["size"].split("x")[0])
    return points * int(entry["scale"].rstrip("x"))


app_icon = catalog / "AppIcon.appiconset"
check(app_icon, app_icon_pixels)

# macOS refuses an app icon that omits any rung of the ladder, so the required
# set is asserted independently of what Contents.json happens to list.
required = {
    (16, "1x"), (16, "2x"), (32, "1x"), (32, "2x"), (128, "1x"),
    (128, "2x"), (256, "1x"), (256, "2x"), (512, "1x"), (512, "2x"),
}
declared = set()
if (app_icon / "Contents.json").is_file():
    manifest = json.loads((app_icon / "Contents.json").read_text(encoding="utf-8"))
    for entry in manifest.get("images", []):
        if entry.get("idiom") == "mac":
            declared.add((int(entry["size"].split("x")[0]), entry["scale"]))
for size, scale in sorted(required - declared):
    failures.append(f"AppIcon.appiconset: no {size}x{size}@{scale} entry")

menu_bar = catalog / "MenuBarIcon.imageset"
check(menu_bar, lambda entry: None)

if (menu_bar / "Contents.json").is_file():
    manifest = json.loads((menu_bar / "Contents.json").read_text(encoding="utf-8"))
    intent = manifest.get("properties", {}).get("template-rendering-intent")
    # Without this the status item ships as fixed pixels and turns invisible in
    # one of the two menu bar appearances.
    if intent != "template":
        failures.append(
            f"MenuBarIcon.imageset: rendering intent is {intent!r}, expected 'template'"
        )

if failures:
    print("Asset validation failed:")
    for failure in failures:
        print(f"  {failure}")
    sys.exit(1)

print("Asset validation passed: every declared icon is present and correctly sized.")
PYTHON
