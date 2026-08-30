import importlib.util
import io
import json
import plistlib
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock


SCRIPT_PATH = Path(__file__).parents[1] / "measure-idle-performance.py"


def load_script():
    spec = importlib.util.spec_from_file_location("measure_idle_performance", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class IdlePerformanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = load_script()

    def test_parses_nul_separated_powermetrics_samples_for_target_pid(self):
        samples = [
            {
                "tasks": [
                    {
                        "pid": 42,
                        "name": "NotchFlow",
                        "cputime_ms_per_s": 0.5,
                        "idle_wakeups_per_s": 0.25,
                    },
                    {
                        "pid": 7,
                        "name": "Other",
                        "cputime_ms_per_s": 900,
                        "idle_wakeups_per_s": 900,
                    },
                ]
            },
            {
                "tasks": [
                    {
                        "pid": 42,
                        "name": "NotchFlow",
                        "cputime_ms_per_s": 1.5,
                        "idle_wakeups_per_s": 0.75,
                    }
                ]
            },
        ]
        payload = b"\0".join(plistlib.dumps(sample) for sample in samples)

        parsed = self.script.parse_powermetrics_samples(payload, process_id=42)

        self.assertEqual(parsed.cpu_percentages, [0.05, 0.15])
        self.assertEqual(parsed.wakeups_per_second, [0.25, 0.75])

    def test_evaluates_strict_documented_budgets_and_memory_median(self):
        measurement = self.script.Measurement(
            cpu_percentages=[0.05, 0.09],
            wakeups_per_second=[0.25, 0.75],
            resident_memory_megabytes=[59.0, 30.0, 45.0],
        )

        report = self.script.evaluate_measurement(measurement)

        self.assertTrue(report.passed)
        self.assertAlmostEqual(report.metrics["idle_cpu_percent"].value, 0.07)
        self.assertAlmostEqual(report.metrics["idle_wakeups_per_second"].value, 0.5)
        self.assertAlmostEqual(report.metrics["resident_memory_megabytes"].value, 45.0)

        at_limits = self.script.Measurement(
            cpu_percentages=[0.1],
            wakeups_per_second=[1.0],
            resident_memory_megabytes=[60.0, 60.0, 60.0],
        )
        self.assertFalse(self.script.evaluate_measurement(at_limits).passed)

    def test_main_writes_machine_readable_report_and_returns_failure(self):
        failing_measurement = self.script.Measurement(
            cpu_percentages=[0.2],
            wakeups_per_second=[0.5],
            resident_memory_megabytes=[40.0, 40.0, 40.0],
        )
        stdout = io.StringIO()
        stderr = io.StringIO()

        with (
            mock.patch.object(self.script, "measure_idle_process", return_value=failing_measurement),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            exit_code = self.script.main(["--pid", "42", "--skip-launch", "--idle-wait", "0"])

        report = json.loads(stdout.getvalue())
        self.assertEqual(exit_code, 1)
        self.assertFalse(report["passed"])
        self.assertEqual(report["process"]["pid"], 42)
        self.assertEqual(report["protocol"]["idle_wait_seconds"], 0)
        self.assertIn("FAIL", stderr.getvalue())
        self.assertIn("Idle CPU", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
