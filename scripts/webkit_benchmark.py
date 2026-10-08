#!/usr/bin/env python3
"""Low-overhead Astra WebKit benchmark helper.

The app is intentionally not automated here. WebKit's process ownership is
observable from macOS, while tab ownership is not a public API. Run a manual
scenario in Astra and take snapshots before and after each lifecycle action.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import os
import platform
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Iterable


ROLES = ("astra", "webcontent", "gpu", "network", "other")
SCENARIOS = (
    "one-empty-tab",
    "one-ordinary-website",
    "ten-background-tabs",
    "fifty-restored-tabs",
    "youtube-playing",
    "youtube-paused",
    "youtube-backgrounded",
    "youtube-repeat-navigation-close",
    "multiple-windows-spaces",
    "switch-while-audio-plays",
    "memory-pressure-protected-state",
    "rapid-create-close-restore",
)


def _parse_cpu_time(value: str) -> float:
    pieces = value.split(":")
    try:
        if len(pieces) == 2:
            return float(pieces[0]) * 60 + float(pieces[1])
        if len(pieces) == 3:
            return float(pieces[0]) * 3600 + float(pieces[1]) * 60 + float(pieces[2])
    except ValueError:
        pass
    return 0.0


def _ps_rows() -> list[dict[str, Any]]:
    """Read one process table without inspecting page content or URLs."""
    command = ["ps", "-axo", "pid=,ppid=,rss=,lstart=,comm=,time="]
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    rows: list[dict[str, Any]] = []
    for line in result.stdout.splitlines():
        row = _parse_ps_line(line)
        if row is not None:
            rows.append(row)
    return rows


def _parse_ps_line(line: str) -> dict[str, Any] | None:
    # lstart is five whitespace-separated fields. Keep the executable and
    # cumulative CPU time separate from any command arguments for privacy.
    fields = line.split(None, 8)
    if len(fields) != 9:
        return None
    try:
        pid, ppid = int(fields[0]), int(fields[1])
        rss_kib = float(fields[2])
    except ValueError:
        return None
    executable, cpu_time = fields[8].rsplit(None, 1)
    return {
        "pid": pid,
        "ppid": ppid,
        "rss_bytes": int(rss_kib * 1024),
        "started": " ".join(fields[3:8]),
        "executable": executable.split("/")[-1][:80],
        "cpu_seconds": _parse_cpu_time(cpu_time),
    }


class _RUsageInfoV4(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_ubyte * 16)] + [
        (f"value_{index}", ctypes.c_uint64) for index in range(36)
    ]


def _rusage(pid: int) -> dict[str, Any]:
    """Read public libproc footprint and cumulative CPU for one selected PID."""
    if platform.system() != "Darwin":
        return {}
    try:
        libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
        call = libproc.proc_pid_rusage
        call.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.POINTER(_RUsageInfoV4)]
        call.restype = ctypes.c_int
        value = _RUsageInfoV4()
        if call(pid, 4, ctypes.byref(value)) != 0:
            return {}
        return {
            "footprint_bytes": int(value.value_7),
            "rusage_cpu_nanoseconds": int(value.value_0 + value.value_1),
            "rusage_start_abstime": int(value.value_8),
        }
    except (AttributeError, OSError):
        return {}


def _deduplicate(rows: Iterable[dict[str, Any]], selected: dict[int, str]) -> list[dict[str, Any]]:
    seen: set[tuple[int, str]] = set()
    result: list[dict[str, Any]] = []
    for row in rows:
        identity = (row["pid"], row["started"])
        if identity in seen:
            continue
        seen.add(identity)
        if row["pid"] not in selected:
            continue
        item = dict(row)
        item["identity"] = f"{row['pid']}@{row['started']}"
        item["role"] = selected[row["pid"]]
        item.update(_rusage(row["pid"]))
        result.append(item)
    return result


def _totals(processes: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    totals = {
        role: {"rss_bytes": 0, "footprint_bytes": 0, "footprint_processes": 0, "processes": 0}
        for role in ROLES
    }
    for row in processes:
        total = totals[row["role"]]
        total["rss_bytes"] += row["rss_bytes"]
        if "footprint_bytes" in row:
            total["footprint_bytes"] += row["footprint_bytes"]
            total["footprint_processes"] += 1
        total["processes"] += 1
    return totals


def snapshot(selected: dict[int, str] | None = None) -> dict[str, Any]:
    selected = selected or {}
    all_rows = _ps_rows()
    rows = _deduplicate(all_rows, selected)
    processes = [row for row in rows if row["role"] in ROLES]
    totals = _totals(processes)
    unattributed = [
        {"pid": row["pid"], "identity": f"{row['pid']}@{row['started']}", "executable": row["executable"]}
        for row in all_rows
        if row["executable"].lower().startswith("webkit") and row["pid"] not in selected
    ]
    unavailable = sorted(set(selected) - {row["pid"] for row in processes})
    return {
        "schema": 1,
        "captured_at": time.time(),
        "monotonic": time.monotonic(),
        "host": {
            "os": platform.platform(),
            "machine": platform.machine(),
            "processor_count": os.cpu_count(),
            "python": platform.python_version(),
        },
        "measurement": {
            "cpu_source": "ps cumulative process time; interval CPU is derived from two samples",
            "rss_source": "ps rss; process level; bytes are estimates",
            "tab_attribution": "unavailable from public WebKit APIs",
            "ownership": "only explicitly mapped PIDs are attributed; XPC WebKit helpers remain unattributed",
            "shared_processes": "deduplicated by pid and process start identity",
            "footprint_source": "public proc_pid_rusage RUSAGE_INFO_V4 when available; otherwise unavailable",
        },
        "totals": totals,
        "processes": processes,
        "unattributed_webkit_processes": unattributed,
        "unavailable_selected_pids": unavailable,
    }


def _write(value: Any, destination: str | None) -> None:
    encoded = json.dumps(value, indent=2, sort_keys=True)
    if destination:
        Path(destination).write_text(encoded + "\n", encoding="utf-8")
    else:
        print(encoded)


def _mapping(pids: list[int], webkit_pids: list[str]) -> dict[int, str]:
    selected = {pid: "astra" for pid in pids}
    for value in webkit_pids:
        try:
            pid_text, role = value.split(":", 1)
            pid = int(pid_text)
        except ValueError:
            raise ValueError(f"--webkit-pid must be PID:role, got {value!r}")
        if role not in ("webcontent", "gpu", "network", "other"):
            raise ValueError(f"unsupported process role {role!r}")
        selected[pid] = role
    return selected


def _interval_snapshot(selected: dict[int, str], interval: float) -> dict[str, Any]:
    before = snapshot(selected)
    started = time.monotonic()
    time.sleep(interval)
    after = snapshot(selected)
    elapsed = max(time.monotonic() - started, 1e-9)
    cpu = _cpu_delta(before["processes"], after["processes"])
    return {
        "schema": 1,
        "elapsed_seconds": elapsed,
        "cpu_seconds": cpu,
        "cpu_percent_of_one_core": {role: value / elapsed * 100 for role, value in cpu.items()},
        "before": before,
        "after": after,
    }


def _cpu_delta(before: list[dict[str, Any]], after: list[dict[str, Any]]) -> dict[str, float]:
    before_by_id = {row["identity"]: row for row in before}
    cpu = {role: 0.0 for role in ROLES}
    for row in after:
        old = before_by_id.get(row["identity"])
        if old is not None:
            if "rusage_cpu_nanoseconds" in row and "rusage_cpu_nanoseconds" in old:
                delta = (row["rusage_cpu_nanoseconds"] - old["rusage_cpu_nanoseconds"]) / 1_000_000_000
            else:
                delta = row["cpu_seconds"] - old["cpu_seconds"]
            cpu[row["role"]] += max(0.0, delta)
    return cpu


def _timed(command: list[str], output: str | None, selected: dict[int, str]) -> int:
    before = snapshot(selected)
    started = time.monotonic()
    try:
        process = subprocess.Popen(command)
        status = process.wait()
    except OSError as error:
        print(f"cannot run {command[0]}: {error}", file=sys.stderr)
        return 127
    elapsed_ms = (time.monotonic() - started) * 1000
    after = snapshot(selected)
    record = {
        "schema": 1,
        "command": command,
        "exit_status": status,
        "elapsed_ms": round(elapsed_ms, 3),
        "before": before,
        "after": after,
    }
    _write(record, output)
    return status


def _self_test() -> None:
    parsed = _parse_ps_line("9 1 10 Wed Oct 8 18:00:00 2026 /System/Library/WebKit.WebContent 1:02.50")
    assert parsed is not None and parsed["executable"] == "WebKit.WebContent"
    assert "command" not in parsed
    spaced = _parse_ps_line("9 1 10 Wed Oct 8 18:00:00 2026 /Applications/Xcode-beta 27.2 beta 2.app/Contents/MacOS/Astra 0:00.01")
    assert spaced is not None and spaced["executable"] == "Astra"
    rows = [
        {"pid": 9, "ppid": 1, "rss_bytes": 100, "started": "A", "executable": "WebContent", "cpu_seconds": 1.0},
        {"pid": 9, "ppid": 1, "rss_bytes": 200, "started": "A", "executable": "WebContent", "cpu_seconds": 2.0},
        {"pid": 9, "ppid": 1, "rss_bytes": 300, "started": "B", "executable": "WebContent", "cpu_seconds": 3.0},
    ]
    result = _deduplicate(rows, {9: "webcontent"})
    assert len(result) == 2
    assert result[0]["identity"] != result[1]["identity"]
    assert not _deduplicate(rows, {})
    assert _parse_cpu_time("1:02.50") == 62.5
    before = [{"identity": "9@A", "role": "webcontent", "cpu_seconds": 3.0}]
    after = [{"identity": "9@A", "role": "webcontent", "cpu_seconds": 2.0}]
    assert _cpu_delta(before, after)["webcontent"] == 0.0
    print("webkit_benchmark self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    take = subparsers.add_parser("snapshot", help="capture process memory and CPU")
    take.add_argument("--output", "-o")
    take.add_argument("--pid", type=int, action="append", default=[], help="Astra PID to attribute")
    take.add_argument("--webkit-pid", action="append", default=[], help="Explicit helper mapping PID:role")
    take.add_argument("--interval", type=float, default=0.0, help="Also derive CPU over this many seconds")
    timed = subparsers.add_parser("time", help="time a command and capture before/after snapshots")
    timed.add_argument("--output", "-o")
    timed.add_argument("--pid", type=int, action="append", default=[])
    timed.add_argument("--webkit-pid", action="append", default=[])
    timed.add_argument("command", nargs=argparse.REMAINDER)
    scenarios = subparsers.add_parser("scenarios", help="print the required manual scenario identifiers")
    scenarios.add_argument("--json", action="store_true")
    subparsers.add_parser("self-test", help="run parser and identity assertions")
    arguments = parser.parse_args()
    if arguments.action == "snapshot":
        try:
            selected = _mapping(arguments.pid, arguments.webkit_pid)
        except ValueError as error:
            parser.error(str(error))
        result = _interval_snapshot(selected, arguments.interval) if arguments.interval > 0 else snapshot(selected)
        _write(result, arguments.output)
        return 0
    if arguments.action == "time":
        if not arguments.command:
            parser.error("time requires a command after --")
        command = arguments.command[1:] if arguments.command[0] == "--" else arguments.command
        if not command:
            parser.error("time requires a command after --")
        try:
            selected = _mapping(arguments.pid, arguments.webkit_pid)
        except ValueError as error:
            parser.error(str(error))
        return _timed(command, arguments.output, selected)
    if arguments.action == "scenarios":
        if arguments.json:
            print(json.dumps(list(SCENARIOS), indent=2))
        else:
            print("\n".join(SCENARIOS))
        return 0
    _self_test()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
