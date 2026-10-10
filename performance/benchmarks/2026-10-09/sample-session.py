#!/usr/bin/env python3
"""Passively sample selected process resource counters."""

from __future__ import annotations

import argparse
from datetime import datetime
from datetime import timezone
import importlib.util
import json
import math
from pathlib import Path
import time
import tempfile
from typing import Any


REPO = Path(__file__).resolve().parents[3]
HELPER_PATH = REPO / "scripts" / "webkit_benchmark.py"
HELPER_SPEC = importlib.util.spec_from_file_location("astra_webkit_benchmark", HELPER_PATH)
assert HELPER_SPEC is not None and HELPER_SPEC.loader is not None
HELPER = importlib.util.module_from_spec(HELPER_SPEC)
HELPER_SPEC.loader.exec_module(HELPER)


def parse_pid(value: str) -> tuple[int, str]:
    try:
        pid_text, role = value.split(":", 1)
        pid = int(pid_text)
    except ValueError as error:
        raise argparse.ArgumentTypeError("PID:role is required") from error
    if pid <= 0 or not role:
        raise argparse.ArgumentTypeError("PID must be positive and role must be nonempty")
    return pid, role


def read_rusage(pids: dict[int, str]) -> dict[int, dict[str, int]]:
    return {pid: HELPER._rusage(pid) for pid in pids}


def process_sample(
    pids: dict[int, str],
    original_starts: dict[int, int | None],
    previous: dict[int, dict[str, int]],
) -> tuple[dict[str, Any], dict[int, dict[str, int]], bool]:
    readings = read_rusage(pids)
    processes: list[dict[str, Any]] = []
    interval_cpu_by_role: dict[str, int] = {}
    unavailable: list[int] = []
    astra_exited = False
    for pid, role in pids.items():
        reading = readings[pid]
        start = reading.get("rusage_start_abstime")
        if original_starts[pid] is None and start is not None:
            original_starts[pid] = start
        if start is None or original_starts[pid] != start:
            unavailable.append(pid)
            if role == "astra":
                astra_exited = True
            processes.append({"pid": pid, "role": role, "available": False})
            continue
        item: dict[str, Any] = {"pid": pid, "role": role, "available": True}
        for key in ("rusage_start_abstime", "footprint_bytes", "rss_bytes", "rusage_cpu_nanoseconds"):
            if key in reading:
                item[key] = reading[key]
        old = previous.get(pid)
        if old is not None and "rusage_cpu_nanoseconds" in reading and "rusage_cpu_nanoseconds" in old:
            delta = max(0, reading["rusage_cpu_nanoseconds"] - old["rusage_cpu_nanoseconds"])
            interval_cpu_by_role[role] = interval_cpu_by_role.get(role, 0) + delta
        previous[pid] = reading
        processes.append(item)
    return {
        "monotonic": time.monotonic(),
        "wall_time": datetime.now(timezone.utc).isoformat(),
        "processes": processes,
        "interval_cpu_nanoseconds_by_role": interval_cpu_by_role,
        "unavailable_pids": unavailable,
    }, previous, astra_exited


def write_result(path: Path, result: dict[str, Any]) -> None:
    temporary = path.with_name(path.name + ".tmp")
    try:
        temporary.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def _self_test() -> None:
    pids = {42: "astra", 43: "helper"}
    starts = {42: None, 43: None}
    previous: dict[int, dict[str, int]] = {}
    values = {
        42: {"rusage_start_abstime": 100, "rss_bytes": 10, "rusage_cpu_nanoseconds": 20},
        43: {"rusage_start_abstime": 200, "footprint_bytes": 30, "rusage_cpu_nanoseconds": 40},
    }
    original = globals()["read_rusage"]
    try:
        globals()["read_rusage"] = lambda _: values
        first, previous, stopped = process_sample(pids, starts, previous)
        assert not stopped and first["unavailable_pids"] == []
        values[42] = {"rusage_start_abstime": 101, "rss_bytes": 11, "rusage_cpu_nanoseconds": 30}
        second, _, stopped = process_sample(pids, starts, previous)
        assert stopped and second["processes"][0]["available"] is False
        values[42] = {}
        third, _, stopped = process_sample(pids, starts, previous)
        assert stopped and third["processes"][0]["available"] is False
        assert "footprint_bytes" not in first["processes"][0]
    finally:
        globals()["read_rusage"] = original
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "samples.json"
        write_result(path, {"samples": [1]})
        try:
            write_result(path, {"samples": [object()]})
        except TypeError:
            pass
        else:
            raise AssertionError("invalid samples must not replace the saved result")
        assert json.loads(path.read_text()) == {"samples": [1]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", action="append", type=parse_pid, required=True, help="PID:role, repeatable")
    parser.add_argument("--seconds", type=float, required=True)
    parser.add_argument("--interval", type=float, default=60.0)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    _self_test()
    if arguments.self_test:
        print("sample-session self-test passed")
        return 0
    if not math.isfinite(arguments.seconds) or arguments.seconds < 0 or arguments.seconds > 3600:
        parser.error("seconds must be between 0 and 3600")
    if not math.isfinite(arguments.interval) or not 0 < arguments.interval <= 60:
        parser.error("interval must be positive and no greater than 60 seconds")
    pids = dict(arguments.pid)
    result: dict[str, Any] = {
        "schema": 1,
        "duration_seconds": arguments.seconds,
        "interval_seconds": arguments.interval,
        "processes": [{"pid": pid, "role": role} for pid, role in pids.items()],
        "samples": [],
        "stopped_reason": None,
    }
    starts = {pid: None for pid in pids}
    previous: dict[int, dict[str, int]] = {}
    started = time.monotonic()
    while True:
        sample, previous, astra_exited = process_sample(pids, starts, previous)
        result["samples"].append(sample)
        write_result(arguments.output, result)
        if astra_exited:
            result["stopped_reason"] = "astra_pid_unavailable_or_reused"
            write_result(arguments.output, result)
            break
        if time.monotonic() - started >= arguments.seconds:
            result["stopped_reason"] = "duration_elapsed"
            write_result(arguments.output, result)
            break
        time.sleep(min(arguments.interval, 60.0))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
