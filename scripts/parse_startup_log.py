#!/usr/bin/env python3
"""Parse Astra lifecycle OSLog JSON into process-birth-relative timings."""

import argparse
import csv
import datetime as dt
import json
import sys
from pathlib import Path
from typing import Optional


EVENTS = {
    "startup.main-entered": "process_birth_to_main_log_ms",
    "startup.first-window-presented": "process_birth_to_first_window_ms",
    "startup.first-visible-window-update": "process_birth_to_first_visible_update_ms",
    "startup.first-usable-window": "process_birth_to_first_usable_window_ms",
    "startup.windows-presented": "process_birth_to_all_windows_ms",
    "startup.restoration-complete": "process_birth_to_restoration_complete_ms",
    "startup.deferred-services-scheduled": "process_birth_to_deferred_services_ms",
}
READINESS_FIELDS = ("first_window_visible", "first_window_key", "first_window_hydrated", "first_window_first_responder")
FIELDS = ["run", "pid", *EVENTS.values(), *READINESS_FIELDS]


def timestamp(value: str) -> float:
    value = value.replace("Z", "+00:00")
    try:
        parsed = dt.datetime.fromisoformat(value)
    except ValueError:
        parsed = dt.datetime.strptime(value, "%Y-%m-%d %H:%M:%S.%f%z")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.timestamp()


def message(record: dict) -> str:
    return str(record.get("eventMessage") or record.get("message") or "")


def records(path: Path) -> list[dict]:
    content = path.read_text(encoding="utf-8", errors="replace")
    try:
        decoded = json.loads(content)
    except json.JSONDecodeError:
        decoded = None
    if isinstance(decoded, list):
        return [record for record in decoded if isinstance(record, dict)]
    if isinstance(decoded, dict):
        return [decoded]
    parsed = []
    for line in content.splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(record, dict):
            parsed.append(record)
    return parsed


def parse(path: Path, birth: float, pid: Optional[str] = None) -> dict[str, str]:
    values = {field: "" for field in (*EVENTS.values(), *READINESS_FIELDS)}
    for record in records(path):
        if pid is not None and str(record.get("processID")) != pid:
            continue
        try:
            elapsed = (timestamp(str(record["timestamp"])) - birth) * 1000
        except (KeyError, TypeError, ValueError):
            continue
        if elapsed < 0:
            continue
        event_message = message(record)
        if "[startup.first-window-readiness]" in event_message and not values[READINESS_FIELDS[0]]:
            metadata = set(event_message.split())
            for key, field in zip(("visible", "key", "hydrated", "first_responder"), READINESS_FIELDS):
                values[field] = str(f"{key}=true" in metadata).lower()
        event = next((name for name in EVENTS if f"[{name}]" in event_message), None)
        field = EVENTS.get(event) if event else None
        if field is not None and not values[field]:
            values[field] = f"{elapsed:.1f}"
    return values


def self_test() -> None:
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "log.json"
        path.write_text(json.dumps([
            {"timestamp": "2026-10-10T00:00:00.100Z", "eventMessage": "[startup.main-entered]"},
            {"timestamp": "2026-10-10T00:00:01.200Z", "eventMessage": "[startup.first-window-readiness] first_responder=true hydrated=true key=true visible=true"},
            {"timestamp": "2026-10-10T00:00:01.250Z", "eventMessage": "[startup.first-usable-window] visible=true hydrated=true"},
        ]), encoding="utf-8")
        values = parse(path, timestamp("2026-10-10T00:00:00Z"))
        assert values["process_birth_to_main_log_ms"] == "100.0"
        assert values["process_birth_to_first_usable_window_ms"] == "1250.0"
        assert values["process_birth_to_restoration_complete_ms"] == ""
        assert values["first_window_hydrated"] == "true"

        path.write_text("\n".join([
            json.dumps({"timestamp": "2026-10-10T00:00:00.100Z", "eventMessage": "[startup.main-entered]"}),
            json.dumps({"timestamp": "2026-10-10T00:00:00.200Z", "eventMessage": "[startup.main-entered]"}),
        ]) + "\n", encoding="utf-8")
        assert parse(path, timestamp("2026-10-10T00:00:00Z"))["process_birth_to_main_log_ms"] == "100.0"

        path.write_text(json.dumps([{
            "timestamp": "2026-10-10T00:00:01Z",
            "processID": 7,
            "eventMessage": "[startup.first-window-readiness] first_responder=false hydrated=true key=true visible=true",
        }]), encoding="utf-8")
        content = json.loads(path.read_text())
        content.insert(0, {
            "timestamp": "2026-10-09T23:59:59Z",
            "processID": 7,
            "eventMessage": "[startup.first-window-readiness] first_responder=true hydrated=true key=true visible=true",
        })
        content.insert(1, {
            "timestamp": "2026-10-10T00:00:00.100Z",
            "processID": 8,
            "eventMessage": "[startup.main-entered]",
        })
        path.write_text(json.dumps(content), encoding="utf-8")
        missing = parse(path, timestamp("2026-10-10T00:00:00Z"), "7")
        assert missing["process_birth_to_main_log_ms"] == ""
        assert missing["first_window_first_responder"] == "false"
        assert missing["process_birth_to_first_usable_window_ms"] == ""
    print("Startup log parser self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path, nargs="?")
    parser.add_argument("birth", type=float, nargs="?")
    parser.add_argument("--run", default="")
    parser.add_argument("--pid", default="")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--require-usable", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.log is None or args.birth is None:
        parser.error("log and birth are required unless --self-test is used")
    values = parse(args.log, args.birth, args.pid or None)
    row = {"run": args.run, "pid": args.pid, **values}
    if args.output:
        new_file = not args.output.exists() or args.output.stat().st_size == 0
        with args.output.open("a", newline="", encoding="utf-8") as result:
            writer = csv.DictWriter(result, fieldnames=FIELDS)
            if new_file:
                writer.writeheader()
            writer.writerow(row)
    print(",".join(row[field] for field in FIELDS))
    if args.require_usable:
        required = [
            "process_birth_to_main_log_ms",
            "process_birth_to_first_visible_update_ms",
            "process_birth_to_first_usable_window_ms",
            *READINESS_FIELDS,
        ]
        missing = [field for field in required if not values[field] or (field in READINESS_FIELDS and values[field] != "true")]
        if missing:
            print("Missing required startup measurements: " + ", ".join(missing), file=sys.stderr)
            raise SystemExit(1)


if __name__ == "__main__":
    main()
