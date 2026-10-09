#!/usr/bin/env python3
"""Low-overhead Astra WebKit benchmark helper.

The app is intentionally not automated here. WebKit's process ownership is
observable from macOS, while tab ownership is not a public API. Run a manual
scenario in Astra and take snapshots before and after each lifecycle action.
"""

from __future__ import annotations

import argparse
import ctypes
from functools import lru_cache
import json
import os
import platform
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Iterable


ROLES = ("astra", "webcontent", "gpu", "network", "other")
WEBKIT_HELPER_EXECUTABLES = frozenset({
    "com.apple.WebKit.GPU",
    "com.apple.WebKit.Networking",
    "com.apple.WebKit.WebContent",
})
PS_COMMAND = ["ps", "-wwaxo", "pid=,ppid=,rss=,lstart=,time=,comm="]
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
    result = subprocess.run(PS_COMMAND, check=True, capture_output=True, text=True)
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
    cpu_time, executable = fields[8].split(None, 1)
    return {
        "pid": pid,
        "ppid": ppid,
        "rss_bytes": int(rss_kib * 1024),
        "started": " ".join(fields[3:8]),
        "executable": executable.rsplit("/", 1)[-1][:80],
        "cpu_seconds": _parse_cpu_time(cpu_time),
    }


class _RUsageInfoV4(ctypes.Structure):
    # Public sys/resource.h v4 layout; the unused tail has 25 uint64_t fields.
    _fields_ = [("uuid", ctypes.c_ubyte * 16)] + [
        (name, ctypes.c_uint64) for name in (
            "user_time", "system_time", "pkg_idle_wakeups", "interrupt_wakeups",
            "pageins", "wired_size", "resident_size", "phys_footprint",
            "proc_start_abstime", "proc_exit_abstime",
        )
    ] + [("unused", ctypes.c_uint64 * 25)]


class _MachTimebaseInfo(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


@lru_cache(maxsize=1)
def _mach_timebase() -> tuple[int, int] | None:
    try:
        system = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
        call = system.mach_timebase_info
        call.argtypes = [ctypes.POINTER(_MachTimebaseInfo)]
        call.restype = ctypes.c_int
        value = _MachTimebaseInfo()
        if call(ctypes.byref(value)) == 0 and value.denom > 0:
            return value.numer, value.denom
    except (AttributeError, OSError):
        pass
    return None


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
        result = {
            "footprint_bytes": int(value.phys_footprint),
            "rss_bytes": int(value.resident_size),
            "rusage_start_abstime": int(value.proc_start_abstime),
        }
        timebase = _mach_timebase()
        if timebase is not None:
            numer, denom = timebase
            # libproc CPU counters use Mach ticks, including on Apple Silicon.
            result["rusage_cpu_nanoseconds"] = (value.user_time + value.system_time) * numer // denom
        return result
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
        result.append(item)
    return result


def _totals(processes: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    totals = {
        role: {"rss_bytes": 0, "footprint_bytes": None, "footprint_processes": 0, "processes": 0}
        for role in ROLES
    }
    for row in processes:
        total = totals[row["role"]]
        total["rss_bytes"] += row["rss_bytes"]
        if "footprint_bytes" in row:
            total["footprint_bytes"] = (total["footprint_bytes"] or 0) + row["footprint_bytes"]
            total["footprint_processes"] += 1
        total["processes"] += 1
    return totals


def snapshot(selected: dict[int, str] | None = None) -> dict[str, Any]:
    selected = selected or {}
    all_rows = _ps_rows()
    rows = _deduplicate(all_rows, selected)
    for row in rows:
        row.update(_rusage(row["pid"]))
        if "rusage_start_abstime" in row:
            row["identity"] = f"{row['pid']}@mach:{row['rusage_start_abstime']}"
    processes = [row for row in rows if row["role"] in ROLES]
    totals = _totals(processes)
    unattributed = [
        {"pid": row["pid"], "identity": f"{row['pid']}@{row['started']}", "executable": row["executable"]}
        for row in all_rows
        if row["executable"] in WEBKIT_HELPER_EXECUTABLES and row["pid"] not in selected
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
            "cpu_source": "libproc CPU Mach ticks converted with mach_timebase_info; ps cumulative time fallback; interval deltas",
            "rss_source": "libproc resident size when available; otherwise ps rss; process-level estimates",
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
    if any(pid <= 0 for pid in pids):
        raise ValueError("process IDs must be positive")
    selected = {pid: "astra" for pid in pids}
    for value in webkit_pids:
        try:
            pid_text, role = value.split(":", 1)
            pid = int(pid_text)
        except ValueError:
            raise ValueError(f"--webkit-pid must be PID:role, got {value!r}")
        if pid <= 0:
            raise ValueError("process IDs must be positive")
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
        "command_executable": Path(command[0]).name,
        "exit_status": status,
        "elapsed_ms": round(elapsed_ms, 3),
        "before": before,
        "after": after,
    }
    _write(record, output)
    return status


def _self_test() -> None:
    assert PS_COMMAND[-1].endswith("comm=")
    assert "args=" not in PS_COMMAND[-1]
    parsed = _parse_ps_line("9 1 10 Wed Oct 8 18:00:00 2026 1:02.50 /System/Library/WebKit.WebContent")
    assert parsed is not None and parsed["executable"] == "WebKit.WebContent"
    assert "command" not in parsed
    spaced = _parse_ps_line("9 1 10 Wed Oct 8 18:00:00 2026 0:00.01 /Applications/Xcode-beta 27.2 beta 2.app/Contents/MacOS/Astra")
    assert spaced is not None and spaced["executable"] == "Astra"
    unbounded = _parse_ps_line("9 1 10 Wed Oct 8 18:00:00 2026 0:00.01 /System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent")
    assert unbounded is not None and unbounded["executable"] == "com.apple.WebKit.WebContent"
    assert "com.apple.WebKit.WebContent" in WEBKIT_HELPER_EXECUTABLES
    assert "WebKit.WebContent" not in WEBKIT_HELPER_EXECUTABLES
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
        if not 0 <= arguments.interval <= 60:
            parser.error("interval must be finite and between 0 and 60 seconds")
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
