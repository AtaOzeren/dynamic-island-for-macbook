import re
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).parents[2]
CASK_PATH = PROJECT_ROOT / "Casks" / "notchflow.rb"
CHECKLIST_PATH = PROJECT_ROOT / "docs" / "HOMEBREW_SUBMISSION.md"


class HomebrewCaskTests(unittest.TestCase):
    def test_cask_matches_direct_release_artifact(self):
        cask = CASK_PATH.read_text(encoding="utf-8")

        self.assertIn('cask "notchflow" do', cask)
        self.assertIn('version "1.0.0"', cask)
        self.assertIn(
            "releases/download/v#{version}/NotchFlow-#{version}-direct.dmg", cask
        )
        self.assertIn('app "NotchFlow.app"', cask)

    def test_cask_declares_required_metadata_and_cleanup(self):
        cask = CASK_PATH.read_text(encoding="utf-8")

        required_stanzas = (
            'sha256 "REPLACE_WITH_NOTARIZED_DMG_SHA256"',
            'name "NotchFlow"',
            'desc "Live activities and AI agent status in the MacBook notch"',
            'homepage "https://github.com/AtaOzeren/dynamic-island-for-macbook"',
            "strategy :github_latest",
            "depends_on macos: :sonoma",
            '"~/Library/Application Support/NotchFlow"',
            '"~/Library/Preferences/com.notchflow.NotchFlow.plist"',
        )

        for stanza in required_stanzas:
            with self.subTest(stanza=stanza):
                self.assertIn(stanza, cask)

    def test_cask_has_balanced_blocks(self):
        cask = CASK_PATH.read_text(encoding="utf-8")
        block_starts = len(re.findall(r"\bdo\s*$", cask, flags=re.MULTILINE))
        block_ends = len(re.findall(r"^\s*end$", cask, flags=re.MULTILINE))

        self.assertEqual(block_starts, block_ends)

    def test_submission_checklist_keeps_notarized_release_gate_explicit(self):
        checklist = CHECKLIST_PATH.read_text(encoding="utf-8")

        required_steps = (
            "must not be submitted",
            "Developer ID",
            "notarized",
            "xcrun stapler validate",
            "spctl --assess",
            "REPLACE_WITH_NOTARIZED_DMG_SHA256",
            "brew audit --cask --new --online notchflow",
            "brew install --cask notchflow",
            "brew uninstall --cask --zap notchflow",
            ".omo/evidence/task-71-notchflow-v1.log",
        )

        for step in required_steps:
            with self.subTest(step=step):
                self.assertIn(step, checklist)


if __name__ == "__main__":
    unittest.main()
