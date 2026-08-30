import os
import plistlib
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / "package-direct.sh"


class DirectPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.bin_directory = self.root / "bin"
        self.bin_directory.mkdir()
        self.command_log = self.root / "commands.log"
        self._write_fake_tools()

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_ad_hoc_mode_builds_signs_packages_and_reports_skips(self):
        result = self._run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.command_log.read_text(encoding="utf-8")
        self.assertIn('-scheme NotchFlow (Direct)', commands)
        self.assertIn("-configuration Direct", commands)
        self.assertIn("-derivedDataPath", commands)
        self.assertIn("CODE_SIGNING_ALLOWED=NO clean build", commands)
        self.assertIn(
            "codesign --force --deep --options runtime --entitlements ", commands
        )
        self.assertIn("NotchFlow-Direct.entitlements --sign -", commands)
        self.assertIn("hdiutil create -volname NotchFlow -format UDZO", commands)
        self.assertIn("SKIPPED (no membership): Developer ID signing", result.stdout)
        self.assertIn("SKIPPED: notarization", result.stdout)
        self.assertIn("SKIPPED: stapling", result.stdout)

        stage_directory = self.root / "stage-capture"
        self.assertTrue((stage_directory / "NotchFlow.app").is_dir())
        self.assertTrue((stage_directory / "Applications").is_symlink())
        self.assertEqual(os.readlink(stage_directory / "Applications"), "/Applications")

        disk_image = self.root / "dist" / "NotchFlow-1.2.3-direct.dmg"
        checksum = self.root / "dist" / "NotchFlow-1.2.3-direct.dmg.sha256"
        self.assertTrue(disk_image.is_file())
        self.assertIn(disk_image.name, checksum.read_text(encoding="utf-8"))

    def test_developer_id_mode_signs_notarizes_and_staples_app_and_dmg(self):
        result = self._run_script(
            {
                "DEVELOPER_ID_APPLICATION": "Developer ID Application: Example (TEAMID)",
                "NOTARYTOOL_KEYCHAIN_PROFILE": "notchflow-notary",
            }
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.command_log.read_text(encoding="utf-8")
        self.assertIn(
            "codesign --force --deep --options runtime --entitlements ",
            commands,
        )
        self.assertIn(
            "NotchFlow-Direct.entitlements --timestamp --sign "
            "Developer ID Application: Example (TEAMID)",
            commands,
        )
        self.assertEqual(commands.count("notarytool submit"), 2)
        self.assertIn("notarytool submit", commands)
        self.assertIn("--keychain-profile notchflow-notary --wait", commands)
        self.assertIn("stapler staple", commands)
        self.assertIn("stapler validate", commands)
        self.assertNotIn("SKIPPED", result.stdout)

    def test_partial_credentials_fail_before_build(self):
        result = self._run_script(
            {"DEVELOPER_ID_APPLICATION": "Developer ID Application: Example (TEAMID)"}
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "DEVELOPER_ID_APPLICATION and NOTARYTOOL_KEYCHAIN_PROFILE must be set together",
            result.stderr,
        )
        self.assertFalse(self.command_log.exists())

    def test_project_declares_the_version_fields_used_for_artifact_naming(self):
        project_root = SCRIPT_PATH.parents[1]
        info_plist = plistlib.loads(
            (project_root / "NotchFlow" / "Info.plist").read_bytes()
        )
        project_settings = (
            project_root / "NotchFlow.xcodeproj" / "project.pbxproj"
        ).read_text(encoding="utf-8")

        self.assertEqual(
            info_plist["CFBundleShortVersionString"], "$(MARKETING_VERSION)"
        )
        self.assertEqual(info_plist["CFBundleVersion"], "$(CURRENT_PROJECT_VERSION)")
        self.assertEqual(project_settings.count("MARKETING_VERSION = 1.0.0;"), 4)
        self.assertEqual(project_settings.count("CURRENT_PROJECT_VERSION = 1;"), 4)

    def test_release_workflow_uses_the_direct_packaging_pipeline(self):
        workflow = (
            SCRIPT_PATH.parents[1] / ".github" / "workflows" / "release.yml"
        ).read_text(encoding="utf-8")

        self.assertIn("run: ./scripts/package-direct.sh", workflow)
        self.assertIn("security import", workflow)
        self.assertIn("xcrun notarytool store-credentials", workflow)
        self.assertIn("NotchFlow-*-direct.dmg", workflow)
        self.assertNotIn("NotchFlow-$RELEASE_TAG-direct.zip", workflow)

    def test_ci_ad_hoc_mode_does_not_require_membership_secrets(self):
        result = self._run_script(
            {
                "CI": "true",
                "GITHUB_ACTIONS": "true",
                "GITHUB_REF_NAME": "v1.0.0",
            }
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SKIPPED (no membership): Developer ID signing", result.stdout)
        self.assertIn("SKIPPED: notarization", result.stdout)
        self.assertIn("SKIPPED: stapling", result.stdout)

    def _run_script(self, environment=None):
        output_directory = self.root / "dist"
        derived_data = self.root / "DerivedData"
        process_environment = os.environ.copy()
        for key in (
            "DEVELOPER_ID_APPLICATION",
            "NOTARYTOOL_KEYCHAIN_PROFILE",
            "NOTARYTOOL_KEYCHAIN",
        ):
            process_environment.pop(key, None)
        process_environment.update(
            {
                "PATH": f"{self.bin_directory}:{process_environment['PATH']}",
                "COMMAND_LOG": str(self.command_log),
                "OUTPUT_DIR": str(output_directory),
                "DERIVED_DATA_PATH": str(derived_data),
                "PACKAGE_STAGE_PATH": str(self.root / "stage-capture"),
            }
        )
        process_environment.update(environment or {})
        return subprocess.run(
            ["/bin/bash", str(SCRIPT_PATH)],
            cwd=SCRIPT_PATH.parents[1],
            env=process_environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def _write_fake_tools(self):
        self._write_executable(
            "xcodebuild",
            r"""
            #!/bin/bash
            set -euo pipefail
            printf 'xcodebuild %s\n' "$*" >> "$COMMAND_LOG"
            derived_data=''
            while [ "$#" -gt 0 ]; do
                if [ "$1" = '-derivedDataPath' ]; then
                    derived_data="$2"
                    shift 2
                    continue
                fi
                shift
            done
            app="$derived_data/Build/Products/Direct/NotchFlow.app"
            mkdir -p "$app/Contents/MacOS"
            printf '#!/bin/bash\n' > "$app/Contents/MacOS/NotchFlow"
            chmod +x "$app/Contents/MacOS/NotchFlow"
            /usr/bin/python3 - "$app/Contents/Info.plist" <<'PYTHON'
            import plistlib
            import sys

            with open(sys.argv[1], 'wb') as plist:
                plistlib.dump({
                    'CFBundleExecutable': 'NotchFlow',
                    'CFBundleIdentifier': 'com.notchflow.app',
                    'CFBundleShortVersionString': '1.2.3',
                }, plist)
            PYTHON
            """,
        )
        self._write_executable(
            "security",
            r"""
            #!/bin/bash
            set -euo pipefail
            printf 'security %s\n' "$*" >> "$COMMAND_LOG"
            if [ "${FAKE_SECURITY_MISSING_IDENTITY:-0}" = '1' ]; then
                exit 1
            fi
            printf '1) ABC "Developer ID Application: Example (TEAMID)"\n'
            """,
        )
        self._write_executable(
            "codesign",
            r"""
            #!/bin/bash
            set -euo pipefail
            printf 'codesign %s\n' "$*" >> "$COMMAND_LOG"
            """,
        )
        self._write_executable(
            "hdiutil",
            r"""
            #!/bin/bash
            set -euo pipefail
            printf 'hdiutil %s\n' "$*" >> "$COMMAND_LOG"
            output="${!#}"
            mkdir -p "$(dirname "$output")"
            printf 'fake disk image\n' > "$output"
            """,
        )
        self._write_executable(
            "xcrun",
            r"""
            #!/bin/bash
            set -euo pipefail
            printf 'xcrun %s\n' "$*" >> "$COMMAND_LOG"
            """,
        )

    def _write_executable(self, name, contents):
        executable = self.bin_directory / name
        executable.write_text(textwrap.dedent(contents).lstrip(), encoding="utf-8")
        executable.chmod(0o755)


if __name__ == "__main__":
    unittest.main()
