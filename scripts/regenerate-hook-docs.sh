#!/bin/bash
# Rewrites the fenced hook snippets in docs/07-ai-integration.md from
# HookSnippetGenerator, so the doc-drift test has a single-command fix rather
# than a copy-by-hand step every time a hook changes.
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
DOC="$PROJECT_ROOT/docs/07-ai-integration.md"
DUMP_DIR=$(mktemp -d)
DUMP_TEST="$PROJECT_ROOT/Tests/NotchFlowCoreTests/HookSnippetDocRegeneration.swift"

cleanup() {
    rm -rf "$DUMP_DIR"
    rm -f "$DUMP_TEST"
}
trap cleanup EXIT

cat > "$DUMP_TEST" <<SWIFT
import Foundation
import Testing

@testable import NotchFlowCore

/// Written and removed by scripts/regenerate-hook-docs.sh. The generator is
/// only reachable from a target that links NotchFlowCore, and the test target
/// is the one that already does.
@Suite("HookSnippetDocRegeneration")
struct HookSnippetDocRegenerationTests {
    @Test("dump")
    func dump() throws {
        let directory = URL(fileURLWithPath: "$DUMP_DIR", isDirectory: true)
        let generator = HookSnippetGenerator()
        try Data(generator.claudeCodeSettingsFragment().utf8)
            .write(to: directory.appending(path: "claude-code.txt"))
        try Data(generator.codexNotifyFragment().utf8)
            .write(to: directory.appending(path: "codex.txt"))
        try Data(generator.openCodePluginFile().utf8)
            .write(to: directory.appending(path: "opencode.txt"))
    }
}
SWIFT

echo "==> Generating snippets"
swift test --filter HookSnippetDocRegeneration > /dev/null

echo "==> Rewriting $DOC"
DUMP_DIR="$DUMP_DIR" DOC="$DOC" python3 - <<'PY'
import os
import pathlib
import re

doc_path = pathlib.Path(os.environ["DOC"])
dump_dir = pathlib.Path(os.environ["DUMP_DIR"])
doc = doc_path.read_text()

for marker in ("claude-code", "codex", "opencode"):
    body = (dump_dir / f"{marker}.txt").read_text().rstrip("\n")
    pattern = r"(<!-- notchflow-snippet: %s -->\n```[a-zA-Z]*\n)(.*?)(\n```)" % re.escape(marker)
    match = re.search(pattern, doc, re.S)
    if match is None:
        raise SystemExit(f"no snippet block for {marker} in {doc_path}")
    doc = doc[: match.start(2)] + body + doc[match.end(2) :]

doc_path.write_text(doc)
print(f"rewrote {len(list(dump_dir.glob('*.txt')))} snippets")
PY

echo "==> Done"
