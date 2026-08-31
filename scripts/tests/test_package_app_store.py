import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / "package-app-store.sh"


class AppStorePackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.bin_directory = self.root / "bin"
        self.bin_directory.mkdir()
        self.command_log = self.root / "commands.log"
        self._write_fake_tools()

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_membership_free_mode_archives_validates_and_reports_skips(self):
        result = self._run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.command_log.read_text(encoding="utf-8")
        self.assertIn('-scheme NotchFlow (App Store)', commands)
        self.assertIn("-configuration AppStore", commands)
        self.assertIn("CODE_SIGNING_ALLOWED=NO archive", commands)
        self.assertIn("check-assets", commands)
        self.assertIn("check-forbidden-symbols", commands)
        self.assertIn("SKIPPED (no membership): distribution signing", result.stdout)
        self.assertIn("Local validation completed with zero errors", result.stdout)

    def test_member_mode_uses_team_and_verifies_signature(self):
        result = self._run_script({"APPLE_TEAM_ID": "TEAM123"})

        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.command_log.read_text(encoding="utf-8")
        self.assertIn("DEVELOPMENT_TEAM=TEAM123 -allowProvisioningUpdates archive", commands)
        self.assertIn("codesign --verify --deep --strict --verbose=2", commands)
        self.assertIn("spctl --assess --type execute --verbose=2", commands)
        self.assertNotIn("SKIPPED", result.stdout)

    def _run_script(self, extra_environment=None):
        output_directory = self.root / "output"
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{self.bin_directory}:{environment['PATH']}",
                "OUTPUT_DIR": str(output_directory),
                "DERIVED_DATA_PATH": str(self.root / "derived-data"),
                "COMMAND_LOG": str(self.command_log),
                "ASSET_CHECK_PATH": str(self.bin_directory / "check-assets.sh"),
                "FORBIDDEN_SYMBOL_CHECK_PATH": str(
                    self.bin_directory / "check-forbidden-symbols.sh"
                ),
            }
        )
        environment.update(extra_environment or {})
        return subprocess.run(
            ["bash", str(SCRIPT_PATH)],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )

    def _write_fake_tools(self):
        self._write_tool(
            "xcodebuild",
            """
            archive_path=""
            previous=""
            for argument in "$@"; do
                if [ "$previous" = "-archivePath" ]; then archive_path="$argument"; fi
                previous="$argument"
            done
            mkdir -p "$archive_path/Products/Applications/NotchFlow.app/Contents/MacOS"
            touch "$archive_path/Products/Applications/NotchFlow.app/Contents/MacOS/NotchFlow"
            touch "$archive_path/Products/Applications/NotchFlow.app/Contents/Info.plist"
            printf 'xcodebuild %s\n' "$*" >> "$COMMAND_LOG"
            """,
        )
        self._write_tool("plutil", "printf 'plutil %s\n' \"$*\" >> \"$COMMAND_LOG\"")
        self._write_tool(
            "defaults",
            "printf 'defaults %s\n' \"$*\" >> \"$COMMAND_LOG\"; printf 'com.notchflow.NotchFlow\n'",
        )
        self._write_tool("codesign", "printf 'codesign %s\n' \"$*\" >> \"$COMMAND_LOG\"")
        self._write_tool("spctl", "printf 'spctl %s\n' \"$*\" >> \"$COMMAND_LOG\"")

        self._write_guard("check-assets.sh", "check-assets")
        self._write_guard("check-forbidden-symbols.sh", "check-forbidden-symbols")

    def _write_guard(self, name, label):
        wrapper = self.bin_directory / name
        wrapper.write_text(
            f'#!/bin/bash\nprintf "{label} %s\\n" "$*" >> "$COMMAND_LOG"\n',
            encoding="utf-8",
        )
        wrapper.chmod(0o755)

    def _write_tool(self, name, body):
        path = self.bin_directory / name
        path.write_text(
            "#!/bin/bash\nset -e\n" + textwrap.dedent(body).strip() + "\n",
            encoding="utf-8",
        )
        path.chmod(0o755)


if __name__ == "__main__":
    unittest.main()
