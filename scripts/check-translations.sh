#!/bin/bash
set -euo pipefail

# Every catalog must carry every language every other catalog carries: a key
# translated in KerNotchUI but missed in KerNotchCore is a settings window
# with two languages in it, and the app never fails loudly for a missing
# translation — it falls back to the key, which reads as correct English.
CATALOGS=(
    "Sources/KerNotchCore/Resources/Localizable.xcstrings"
    "Sources/KerNotchUI/Resources/Localizable.xcstrings"
    "KerNotch/Localizable.xcstrings"
)

python3 - "${CATALOGS[@]}" <<'PYTHON'
import json
import re
import sys

def translatable_words(text):
    """How many real words a string carries, ignoring format specifiers."""
    return len([word for word in re.sub(r"%(\d+\$)?[@a-z]+", " ", text).split() if word])


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
            elif language != source and len(values) == 1 and values[0] == key and translatable_words(key) > 1:
                # A single word can legitimately be identical across languages
                # ("KerNotch", and "%lld agents" in French); a whole phrase that
                # is byte-identical to its English is an untranslated entry
                # someone pasted through. Format specifiers are not words: they
                # are the same in every language by definition.
                gaps.append(f"{path}: [{language}] untranslated — {key!r}")

if gaps:
    print("Translation Guard Failure: incomplete localization")
    for gap in gaps:
        print(f"  {gap}")
    sys.exit(1)

total = sum(len(catalog["strings"]) for catalog in catalogs.values())
print(f"Translation Guard Passed: {total} keys complete in {', '.join(sorted(languages))}")
PYTHON
