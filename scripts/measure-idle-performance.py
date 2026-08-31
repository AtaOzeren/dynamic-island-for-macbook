#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import plistlib
import signal
import statistics
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Sequence


PROCESS_NAME = "NotchFlow"
DEFAULT_APP_PATH = Path(".build/debug/NotchFlow")
IDLE_WAIT_SECONDS = 60
SAMPLE_COUNT = 60
SAMPLE_INTERVAL_MILLISECONDS = 1_000
MEMORY_SAMPLE_COUNT = 3
MEMORY_SAMPLE_INTERVAL_SECONDS = 20
CPU_BUDGET_PERCENT = 0.1
WAKEUPS_BUDGET_PER_SECOND = 1.0
MEMORY_BUDGET_MEGABYTES = 60.0


class MeasurementError(RuntimeError):
    pass


@dataclass(frozen=True)
class PowermetricsSamples:
    cpu_percentages: list[float]
    wakeups_per_second: list[float]


@dataclass(frozen=True)
class Measurement:
    cpu_percentages: list[float]
    wakeups_per_second: list[float]
    resident_memory_megabytes: list[float]


@dataclass(frozen=True)
class MetricResult:
    label: str
    value: float
    budget: float
    unit: str
    comparison: str
    passed: bool
    sample_count: int


@dataclass(frozen=True)
class EvaluationReport:
    passed: bool
    metrics: dict[str, MetricResult]


@dataclass(frozen=True)
class ProcessDetails:
    name: str
    pid: int
    launched_by_script: bool


def parse_arguments(arguments: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Measure NotchFlow's idle CPU, wakeups, and resident memory budgets."
    )
    parser.add_argument(
        "--app",
        type=Path,
        default=DEFAULT_APP_PATH,
        help=f"executable or .app to launch (default: {DEFAULT_APP_PATH})",
    )
    parser.add_argument("--pid", type=int, help="measure an already running process")
    parser.add_argument(
        "--skip-launch",
        action="store_true",
        help="do not launch the app; requires --pid or one running NotchFlow process",
    )
    parser.add_argument(
        "--idle-wait",
        type=nonnegative_int,
        default=IDLE_WAIT_SECONDS,
        metavar="SECONDS",
        help=f"seconds to wait before sampling (default: {IDLE_WAIT_SECONDS})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="also write the JSON report to this path",
    )
    return parser.parse_args(arguments)


def nonnegative_int(value: str) -> int:
    parsed = int(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be nonnegative")
    return parsed


def parse_powermetrics_samples(payload: bytes, process_id: int) -> PowermetricsSamples:
    cpu_percentages = []
    wakeups_per_second = []

    for raw_sample in payload.split(b"\0"):
        if not raw_sample.strip():
            continue

        sample = plistlib.loads(raw_sample)
        task = next(
            (task for task in sample.get("tasks", []) if task.get("pid") == process_id),
            None,
        )
        if task is None:
            raise MeasurementError(f"powermetrics sample does not contain PID {process_id}")

        cpu_milliseconds_per_second = numeric_field(task, "cputime_ms_per_s")
        cpu_percentages.append(cpu_milliseconds_per_second / 10.0)
        wakeups_per_second.append(numeric_field(task, "idle_wakeups_per_s"))

    if not cpu_percentages:
        raise MeasurementError("powermetrics returned no samples")

    return PowermetricsSamples(cpu_percentages, wakeups_per_second)


def numeric_field(task: dict, key: str) -> float:
    value = task.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise MeasurementError(f"powermetrics task is missing numeric field {key!r}")
    return float(value)


def evaluate_measurement(measurement: Measurement) -> EvaluationReport:
    require_samples(measurement.cpu_percentages, "CPU")
    require_samples(measurement.wakeups_per_second, "wakeups")
    require_samples(measurement.resident_memory_megabytes, "resident memory")

    metrics = {
        "idle_cpu_percent": metric_result(
            "Idle CPU",
            statistics.fmean(measurement.cpu_percentages),
            CPU_BUDGET_PERCENT,
            "%",
            len(measurement.cpu_percentages),
        ),
        "idle_wakeups_per_second": metric_result(
            "Idle wakeups",
            statistics.fmean(measurement.wakeups_per_second),
            WAKEUPS_BUDGET_PER_SECOND,
            "/s",
            len(measurement.wakeups_per_second),
        ),
        "resident_memory_megabytes": metric_result(
            "Resident memory",
            statistics.median(measurement.resident_memory_megabytes),
            MEMORY_BUDGET_MEGABYTES,
            "MB",
            len(measurement.resident_memory_megabytes),
        ),
    }
    return EvaluationReport(all(metric.passed for metric in metrics.values()), metrics)


def require_samples(values: Sequence[float], label: str) -> None:
    if not values:
        raise MeasurementError(f"no {label} samples were collected")


def metric_result(
    label: str,
    value: float,
    budget: float,
    unit: str,
    sample_count: int,
) -> MetricResult:
    return MetricResult(label, value, budget, unit, "<", value < budget, sample_count)


def resolve_executable(path: Path) -> Path:
    if path.suffix == ".app":
        executable = path / "Contents" / "MacOS" / path.stem
    else:
        executable = path
    if not executable.is_file():
        raise MeasurementError(f"app executable not found: {executable}")
    return executable


def find_running_process_id() -> int:
    result = subprocess.run(
        ["/usr/bin/pgrep", "-x", PROCESS_NAME],
        check=False,
        capture_output=True,
        text=True,
    )
    process_ids = [int(value) for value in result.stdout.split()]
    if len(process_ids) != 1:
        raise MeasurementError(
            f"expected exactly one running {PROCESS_NAME} process, found {len(process_ids)}"
        )
    return process_ids[0]


def launch_process(path: Path) -> subprocess.Popen:
    executable = resolve_executable(path)
    process = subprocess.Popen(
        [str(executable.resolve())],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    time.sleep(1)
    if process.poll() is not None:
        raise MeasurementError(f"{PROCESS_NAME} exited before idle measurement began")
    return process


def collect_powermetrics(process_id: int) -> PowermetricsSamples:
    command = [
        "/usr/bin/powermetrics",
        "--format",
        "plist",
        "--samplers",
        "tasks",
        "--show-process-energy",
        "--show-process-samp-norm",
        "--sample-rate",
        str(SAMPLE_INTERVAL_MILLISECONDS),
        "--sample-count",
        str(SAMPLE_COUNT),
    ]
    if os.geteuid() != 0:
        command = ["/usr/bin/sudo", "-n", *command]

    result = subprocess.run(command, check=False, capture_output=True)
    if result.returncode != 0:
        error = result.stderr.decode(errors="replace").strip()
        if "password is required" in error:
            error += "; run `sudo -v` before starting this unattended measurement"
        raise MeasurementError(f"powermetrics failed: {error or 'unknown error'}")

    samples = parse_powermetrics_samples(result.stdout, process_id)
    if len(samples.cpu_percentages) != SAMPLE_COUNT:
        raise MeasurementError(
            f"powermetrics returned {len(samples.cpu_percentages)} of {SAMPLE_COUNT} samples"
        )
    return samples


def collect_resident_memory(process_id: int) -> list[float]:
    samples = []
    for index in range(MEMORY_SAMPLE_COUNT):
        if index:
            time.sleep(MEMORY_SAMPLE_INTERVAL_SECONDS)
        result = subprocess.run(
            ["/bin/ps", "-o", "rss=", "-p", str(process_id)],
            check=False,
            capture_output=True,
            text=True,
        )
        try:
            resident_kilobytes = int(result.stdout.strip())
        except ValueError as error:
            raise MeasurementError(f"could not read resident memory for PID {process_id}") from error
        samples.append(resident_kilobytes / 1024.0)
    return samples


def measure_idle_process(process_id: int) -> Measurement:
    powermetrics = collect_powermetrics(process_id)
    memory = collect_resident_memory(process_id)
    return Measurement(
        powermetrics.cpu_percentages,
        powermetrics.wakeups_per_second,
        memory,
    )


def build_json_report(
    process: ProcessDetails,
    report: EvaluationReport,
    idle_wait_seconds: int,
) -> dict:
    return {
        "schema_version": 1,
        "measured_at": datetime.now(timezone.utc).isoformat(),
        "passed": report.passed,
        "process": asdict(process),
        "protocol": {
            "idle_wait_seconds": idle_wait_seconds,
            "powermetrics_sample_count": SAMPLE_COUNT,
            "powermetrics_interval_milliseconds": SAMPLE_INTERVAL_MILLISECONDS,
            "memory_sample_count": MEMORY_SAMPLE_COUNT,
            "memory_interval_seconds": MEMORY_SAMPLE_INTERVAL_SECONDS,
        },
        "metrics": {key: asdict(metric) for key, metric in report.metrics.items()},
    }


def print_human_summary(report: EvaluationReport) -> None:
    print("NotchFlow idle performance: " + ("PASS" if report.passed else "FAIL"), file=sys.stderr)
    for metric in report.metrics.values():
        status = "PASS" if metric.passed else "FAIL"
        print(
            f"  {status}  {metric.label}: {metric.value:.3f}{metric.unit} "
            f"(budget {metric.comparison} {metric.budget:g}{metric.unit}, "
            f"n={metric.sample_count})",
            file=sys.stderr,
        )


def stop_process(process: subprocess.Popen | None) -> None:
    if process is None or process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()


def main(arguments: Sequence[str] | None = None) -> int:
    options = parse_arguments(arguments)
    launched_process = None

    try:
        if options.skip_launch:
            process_id = options.pid or find_running_process_id()
        else:
            if options.pid is not None:
                raise MeasurementError("--pid requires --skip-launch")
            launched_process = launch_process(options.app)
            process_id = launched_process.pid

        process = ProcessDetails(PROCESS_NAME, process_id, launched_process is not None)
        if options.idle_wait:
            print(
                f"Waiting {options.idle_wait}s for {PROCESS_NAME} to become idle...",
                file=sys.stderr,
            )
            time.sleep(options.idle_wait)

        measurement = measure_idle_process(process_id)
        evaluation = evaluate_measurement(measurement)
        json_report = build_json_report(process, evaluation, options.idle_wait)
        json_output = json.dumps(json_report, indent=2, sort_keys=True)
        print(json_output)
        if options.output:
            options.output.parent.mkdir(parents=True, exist_ok=True)
            options.output.write_text(json_output + "\n", encoding="utf-8")
        print_human_summary(evaluation)
        return 0 if evaluation.passed else 1
    except (MeasurementError, OSError, plistlib.InvalidFileException) as error:
        print(f"Idle performance measurement error: {error}", file=sys.stderr)
        return 2
    finally:
        stop_process(launched_process)


if __name__ == "__main__":
    raise SystemExit(main())
