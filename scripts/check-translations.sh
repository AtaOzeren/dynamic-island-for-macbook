#!/bin/bash
set -euo pipefail

# Every catalog must carry every language every other catalog carries: a key
# translated in NotchFlowUI but missed in NotchFlowCore is a settings window
# with two languages in it, and the app never fails loudly for a missing
# translation — it falls back to the key, which reads as correct English.
CATALOGS=(
    "Sources/NotchFlowCore/Resources/Localizable.xcstrings"
    "Sources/NotchFlowUI/Resources/Localizable.xcstrings"
    "NotchFlow/Localizable.xcstrings"
)

python3 - "${CATALOGS[@]}" <<'PYTHON'
import json
import sys

paths = sys.argv[1:]
catalogs = {path: json.load(open(path, encoding="utf-8")) for path in paths}

languages = set()
for catalog in catalogs.values():
    for entry in catalog["strings"].values():
        languages.update(entry.get("localizations", {}))

gaps = []
for path, catalog in catalogs.items():
    source = catalog["sourceLanguage"]
    for key, entry in sorted(catalog["strings"].items()):
        localizations = entry.get("localizations", {})
        for language in sorted(languages):
            unit = localizations.get(language)
            if unit is None:
                gaps.append(f"{path}: [{language}] missing — {key!r}")
                continue

            values = []
            if "stringUnit" in unit:
                values.append(unit["stringUnit"].get("value", ""))
            for variation in unit.get("variations", {}).get("plural", {}).values():
                values.append(variation.get("stringUnit", {}).get("value", ""))

            if not values or not all(value.strip() for value in values):
                gaps.append(f"{path}: [{language}] empty — {key!r}")
            elif language != source and len(values) == 1 and values[0] == key and len(key.split()) > 1:
                # A single-word key can legitimately be identical across
                # languages ("NotchFlow"); a whole phrase that is byte-identical
                # to its English is an untranslated entry someone pasted through.
                gaps.append(f"{path}: [{language}] untranslated — {key!r}")

if gaps:
    print("Translation Guard Failure: incomplete localization")
    for gap in gaps:
        print(f"  {gap}")
    sys.exit(1)

total = sum(len(catalog["strings"]) for catalog in catalogs.values())
print(f"Translation Guard Passed: {total} keys complete in {', '.join(sorted(languages))}")
PYTHON
