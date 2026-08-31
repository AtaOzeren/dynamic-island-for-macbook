import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / "check-app-store-screenshots.sh"
SCREENSHOT_NAMES = (
    "01-music.png",
    "02-timer.png",
    "03-ai-agent.png",
    "04-recording.png",
    "05-settings.png",
)


class AppStoreScreenshotTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary_directory.name)

    def tearDown(self):
        self.temporary_directory.cleanup()

    def test_complete_rgb_set_passes(self):
        for name in SCREENSHOT_NAMES:
            self._write_png(name, 2560, 1600, color_type=2)

        result = self._run_check()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("5 images are upload-ready", result.stdout)

    def test_missing_image_fails(self):
        for name in SCREENSHOT_NAMES[:-1]:
            self._write_png(name, 2560, 1600, color_type=2)

        result = self._run_check()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing 05-settings.png", result.stderr)

    def test_wrong_size_and_alpha_fail(self):
        for name in SCREENSHOT_NAMES:
            self._write_png(name, 1200, 800, color_type=6)

        result = self._run_check()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported size 1200x800", result.stderr)
        self.assertIn("alpha channel is not allowed", result.stderr)

    def _run_check(self):
        return subprocess.run(
            ["bash", str(SCRIPT_PATH), str(self.directory)],
            capture_output=True,
            text=True,
            check=False,
        )

    def _write_png(self, name, width, height, color_type):
        signature = b"\x89PNG\r\n\x1a\n"
        ihdr = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
        chunk = b"IHDR" + ihdr
        png = signature + struct.pack(">I", len(ihdr)) + chunk + struct.pack(">I", zlib.crc32(chunk))
        (self.directory / name).write_bytes(png)


if __name__ == "__main__":
    unittest.main()
