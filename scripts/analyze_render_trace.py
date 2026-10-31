#!/usr/bin/env python3
"""Bounded, streaming analysis of an Instruments exported-tables archive."""

from __future__ import annotations

import argparse
import collections
import json
import math
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


TABLES = {
    "ProcessCPUUsage": "ProcessCPUUsage",
    "ThreadCPUUsage": "ThreadCPUUsage",
    "time-profile": "time-profile",
    "swiftui-updates": "swiftui-updates",
    "swiftui-changes": "swiftui-changes",
    "swiftui-causes": "swiftui-causes",
    "swiftui-update-groups": "swiftui-update-groups",
}
NS_TAGS = {"start-time", "sample-time", "event-time", "duration", "weight", "downstream-cost"}


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def number(text: str | None) -> float | None:
    if text is None:
        return None
    try:
        return float(text.strip())
    except (TypeError, ValueError):
        return None


def scalar(element: ET.Element, refs: dict[str, object]) -> object:
    ref = element.attrib.get("ref")
    if ref:
        if ref not in refs:
            raise ValueError(f"Unresolved Instruments reference: {ref}")
        return refs[ref]
    children = list(element)
    if not children:
        value: object = element.text.strip() if element.text and element.text.strip() else None
    else:
        value = {}
        for child in children:
            name = local(child.tag)
            if name == "sentinel":
                continue
            child_value = scalar(child, refs)
            if name in value:
                value[name] = value[name] if isinstance(value[name], list) else [value[name]]
                value[name].append(child_value)
            else:
                value[name] = child_value
    if "name" in element.attrib:
        if isinstance(value, dict):
            value["name"] = element.attrib["name"]
        else:
            value = {"name": element.attrib["name"], "value": value}
    if "fmt" in element.attrib:
        value = {"value": value, "fmt": element.attrib["fmt"]}
    if "id" in element.attrib:
        refs[element.attrib["id"]] = value
    return value


def raw(value: object) -> object:
    return value.get("value") if isinstance(value, dict) and "value" in value else value


def fmt(value: object) -> str | None:
    return value.get("fmt") if isinstance(value, dict) else None


def text_value(value: object) -> str:
    value = raw(value)
    if isinstance(value, dict):
        return ", ".join(text_value(v) for v in value.values())
    return "" if value is None else str(value)


def duration_seconds(value: object, tag: str = "duration") -> float | None:
    n = number(text_value(value))
    if n is None:
        return None
    # Instruments exported time quantities are integer nanoseconds, including
    # values displayed as µs/ms in fmt.
    return n / 1_000_000_000 if tag in NS_TAGS or tag == "start" else n


def display(value: object) -> str:
    f = fmt(value)
    return f or text_value(value)


def key_count(counter: collections.Counter, limit: int | None = 20) -> list[dict[str, object]]:
    return [{"key": str(k), "count": v} for k, v in counter.most_common(limit)]


def stack_info(value: object) -> tuple[list[str], list[str]]:
    value = raw(value)
    if not isinstance(value, dict):
        return [], []
    if "frames" in value:
        return list(value["frames"]), list(value.get("binaries", []))
    frames: list[str] = []
    binaries: list[str] = []
    entries = value.get("frame", [])
    if not isinstance(entries, list):
        entries = [entries]
    for entry in entries:
        if not isinstance(entry, dict) or "name" not in entry:
            continue
        frames.append(str(entry["name"]))
        binary = entry.get("binary")
        if isinstance(binary, dict) and binary.get("name"):
            binaries.append(str(binary["name"]))
    return frames, binaries


def add_bin(bins: dict[str, float], start: float, end: float, amount: float) -> None:
    if end <= start or amount <= 0:
        return
    first = math.floor(start)
    last = math.floor(max(start, end - 1e-12))
    total = end - start
    for sec in range(first, last + 1):
        left, right = max(start, sec), min(end, sec + 1.0)
        if right > left:
            bins[str(sec)] = bins.get(str(sec), 0.0) + amount * (right - left) / total


def add_count_bin(bins: dict[str, int], timestamp: float) -> None:
    bins[str(math.floor(timestamp))] = bins.get(str(math.floor(timestamp)), 0) + 1


def parse_table(zf: zipfile.ZipFile, member: str, table: str, cpu_window: tuple[float, float] | None = None) -> dict[str, object]:
    refs: dict[str, object] = {}
    columns: list[str] = []
    rows = 0
    starts: list[float] = []
    ends: list[float] = []
    thread = collections.Counter()
    thread_cpu = collections.Counter()
    leaf = collections.Counter()
    inclusive = collections.Counter()
    binaries = collections.Counter()
    categories = collections.Counter()
    descriptions = collections.Counter()
    update_types = collections.Counter()
    view_names = collections.Counter()
    modules = collections.Counter()
    causes = collections.Counter()
    frame_scheduling = collections.Counter()
    bins: dict[str, float] = {}
    cpu_bins: dict[str, float] = {}
    cpu_bin_durations: dict[str, float] = {}
    count_bins: dict[str, int] = {}
    type_durations = collections.Counter()
    view_durations = collections.Counter()
    app_updates = collections.Counter()
    app_updates_in_cpu_window = collections.Counter()
    cpu_seconds = 0.0
    cpu_samples = 0
    weighted_samples = 0.0
    with zf.open(member) as stream:
        for event, element in ET.iterparse(stream, events=("end",)):
            if local(element.tag) == "schema":
                columns = [m.text.strip() for m in element.findall("./col/mnemonic") if m.text and m.text.strip()]
                continue
            if local(element.tag) != "row":
                continue
            rows += 1
            values: dict[str, object] = {}
            children = list(element)
            for index, child in enumerate(children):
                name = columns[index] if index < len(columns) else local(child.tag)
                if local(child.tag) == "sentinel":
                    values[name] = None
                else:
                    values[name] = scalar(child, refs)
                    if name == "stack":
                        stack_frames, stack_binaries = stack_info(values[name])
                        values[name] = {"frames": stack_frames, "binaries": stack_binaries}
                        identifier = child.attrib.get("id")
                        if identifier:
                            refs[identifier] = values[name]
            start = duration_seconds(values.get("start") or values.get("start-time") or values.get("time") or values.get("sample-time") or values.get("timestamp") or values.get("event-time"), "start")
            if start is None:
                start = duration_seconds(values.get("sample-time") or values.get("event-time"), "start")
            dur = duration_seconds(values.get("duration"))
            if start is not None:
                starts.append(start)
                ends.append(start + (dur or 0.0))
            if table in ("ProcessCPUUsage", "ThreadCPUUsage"):
                pct = number(text_value(values.get("cpu-usage") or values.get("system-cpu-percent")))
                if pct is not None and dur is not None:
                    cpu_seconds += pct / 100.0 * dur
                    cpu_samples += 1
                    add_bin(cpu_bins, start or 0.0, (start or 0.0) + dur, pct / 100.0 * dur)
                    add_bin(cpu_bin_durations, start or 0.0, (start or 0.0) + dur, dur)
                if table == "ThreadCPUUsage":
                    name = display(values.get("thread"))
                    thread[name] += 1
                    thread_cpu[name] += pct / 100.0 * dur if pct is not None and dur is not None else 0.0
            elif table == "time-profile":
                weight = duration_seconds(values.get("weight"), "weight")
                if weight is not None:
                    weighted_samples += weight
                frames, bs = stack_info(values.get("stack") or values.get("tagged-backtrace") or values.get("backtrace"))
                if frames:
                    leaf[frames[0]] += weight or 0.0
                    for frame in set(frames):
                        inclusive[frame] += weight or 0.0
                for binary in set(bs):
                    binaries[binary] += weight or 0.0
                thread[display(values.get("thread"))] += 1
            elif table == "swiftui-updates":
                categories[display(values.get("category"))] += 1
                descriptions[display(values.get("description"))] += 1
                update_types[display(values.get("update-type"))] += 1
                view_names[display(values.get("view-name"))] += 1
                modules[display(values.get("module"))] += 1
                if start is not None and dur is not None:
                    add_bin(bins, start, start + dur, dur)
                    add_count_bin(count_bins, start)
                    type_durations[display(values.get("update-type"))] += dur
                    view_durations[display(values.get("view-name"))] += dur
                    if display(values.get("module")) == "astra":
                        owner = f"{display(values.get('update-type'))}: {display(values.get('view-name') or values.get('description'))}"
                        app_updates[owner] += 1
                        if cpu_window and cpu_window[0] <= start <= cpu_window[1]:
                            app_updates_in_cpu_window[owner] += 1
            elif table == "swiftui-changes":
                causes[display(values.get("description"))] += 1
            elif table == "swiftui-causes":
                label = display(values.get("label"))
                changed = display(values.get("changed-properties"))
                causes[f"{label}: {changed}".strip(": ")] += 1
                frame_scheduling[display(values.get("value-type"))] += 1
            elif table == "swiftui-update-groups":
                label = display(values.get("label"))
                inclusive[label] += dur or 0.0
                if start is not None and dur is not None:
                    add_bin(bins, start, start + dur, dur)
            element.clear()
    covered = {
        "start_seconds": min(starts) if starts else None,
        "end_seconds": max(ends) if ends else None,
        "duration_seconds": (max(ends) - min(starts)) if starts else 0.0,
    }
    result: dict[str, object] = {"rows": rows, "covered_window": covered}
    if table in ("ProcessCPUUsage", "ThreadCPUUsage"):
        result.update({"cpu_seconds": cpu_seconds, "cpu_samples": cpu_samples, "threads": key_count(thread), "cpu_seconds_by_thread": dict(thread_cpu), "cpu_seconds_bins": cpu_bins, "average_percent_bins": {k: 100.0 * cpu_bins[k] / cpu_bin_durations[k] for k in cpu_bins if cpu_bin_durations[k]}})
        if table == "ThreadCPUUsage":
            # Summed thread intervals are not elapsed process time.
            result.pop("average_percent_bins")
    if table == "time-profile":
        result.update({"weighted_sample_seconds": weighted_samples, "leaf_symbols": key_count(leaf), "inclusive_symbols": key_count(inclusive), "binaries": key_count(binaries), "threads": key_count(thread)})
    if table == "swiftui-updates":
        result.update({"categories": key_count(categories), "view_descriptions": key_count(descriptions), "modules": key_count(modules), "update_types": key_count(update_types), "view_names": key_count(view_names), "duration_seconds_by_update_type": dict(type_durations), "duration_seconds_by_view_name": dict(view_durations), "duration_bins_seconds": bins, "count_bins": count_bins, "app_updates": key_count(app_updates, None), "app_updates_in_process_cpu_window": key_count(app_updates_in_cpu_window, None)})
    if table in ("swiftui-changes", "swiftui-causes"):
        result["change_event_descriptions"] = key_count(causes)
        if table == "swiftui-causes":
            result["cause_edge_labels"] = key_count(causes)
            result["cause_value_types"] = key_count(frame_scheduling)
    if table == "swiftui-update-groups":
        result.update({"inclusive_duration_seconds_by_label": dict(inclusive), "duration_bins_seconds": bins, "inclusive_duration_is_not_cpu": True})
    return result


def analyze(path: str | Path) -> dict[str, object]:
    result: dict[str, object] = {"input": str(path), "tables": {}, "limitations": [
        "CPU usage is integrated from exported interval percentages; time-profile weights are statistical sample weights, not CPU duration.",
        "SwiftUI durations are inclusive update/group durations and must not be added to CPU totals.",
        "Only selected rows exported by Instruments are represented; table windows may differ.",
    ]}
    with zipfile.ZipFile(path) as zf:
        names = set(zf.namelist())
        cpu_window = None
        for stem, table in TABLES.items():
            member = next((n for n in names if n.endswith(f"/{stem}.xml") or n == f"{stem}.xml"), None)
            if member:
                result["tables"][table] = parse_table(zf, member, table, cpu_window)
                if table == "ProcessCPUUsage":
                    window = result["tables"][table]["covered_window"]
                    cpu_window = (window["start_seconds"], window["end_seconds"])
    windows = [v["covered_window"] for v in result["tables"].values() if v["covered_window"]["start_seconds"] is not None]
    result["covered_window"] = {
        "start_seconds": min(w["start_seconds"] for w in windows) if windows else None,
        "end_seconds": max(w["end_seconds"] for w in windows) if windows else None,
        "duration_seconds": (max(w["end_seconds"] for w in windows) - min(w["start_seconds"] for w in windows)) if windows else 0.0,
    }
    process_window = result["tables"].get("ProcessCPUUsage", {}).get("covered_window")
    if process_window:
        for name in ("swiftui-updates", "swiftui-changes", "swiftui-causes", "swiftui-update-groups"):
            table = result["tables"].get(name)
            if table:
                table["timestamps_beyond_process_cpu_window"] = {
                    "process_cpu_end_seconds": process_window["end_seconds"],
                    "table_end_seconds": table["covered_window"]["end_seconds"],
                    "seconds_after_process_cpu_end": max(0.0, table["covered_window"]["end_seconds"] - process_window["end_seconds"]),
                }
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive")
    parser.add_argument("--json", dest="json_path")
    args = parser.parse_args()
    report = analyze(args.archive)
    payload = json.dumps(report, indent=2, sort_keys=True)
    if args.json_path:
        Path(args.json_path).write_text(payload + "\n", encoding="utf-8")
    print(json.dumps({"tables": list(report["tables"]), "covered_window": report["covered_window"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
