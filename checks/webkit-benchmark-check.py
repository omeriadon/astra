#!/usr/bin/env python3
"""Executable checks for the process-level WebKit benchmark helper."""

from __future__ import annotations

import json
import importlib.util
import os
import platform
import resource
import time
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "scripts" / "webkit_benchmark.py"


def run(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(HARNESS), *arguments],
        check=True,
        capture_output=True,
        text=True,
    )


def main() -> int:
    self_test = run("self-test")
    assert "passed" in self_test.stdout

    scenarios = json.loads(run("scenarios", "--json").stdout)
    assert len(scenarios) == 12
    assert "youtube-playing" in scenarios
    assert "memory-pressure-protected-state" in scenarios

    snapshot = json.loads(run("snapshot").stdout)
    assert snapshot["schema"] == 1
    assert snapshot["measurement"]["tab_attribution"] == "unavailable from public WebKit APIs"
    assert set(snapshot["totals"]) == {"astra", "webcontent", "gpu", "network", "other"}
    identities = [process["identity"] for process in snapshot["processes"]]
    assert len(identities) == len(set(identities))
    for process in snapshot["processes"]:
        assert process["rss_bytes"] >= 0
        assert process["pid"] > 0
        assert process["started"]
    if platform.system() == "Darwin":
        spec = importlib.util.spec_from_file_location("webkit_benchmark_check", HARNESS)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        before_usage = module._rusage(os.getpid())
        before_cpu = resource.getrusage(resource.RUSAGE_SELF)
        deadline = time.monotonic() + 0.03
        while time.monotonic() < deadline:
            pass
        after_usage = module._rusage(os.getpid())
        after_cpu = resource.getrusage(resource.RUSAGE_SELF)
        actual = after_usage["rusage_cpu_nanoseconds"] - before_usage["rusage_cpu_nanoseconds"]
        expected = ((after_cpu.ru_utime + after_cpu.ru_stime) - (before_cpu.ru_utime + before_cpu.ru_stime)) * 1_000_000_000
        assert 0.7 * expected < actual < 1.3 * expected, "Mach tick conversion must match process CPU time"
    print("webkit benchmark checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
