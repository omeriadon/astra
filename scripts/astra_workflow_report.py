#!/usr/bin/env python3
"""Summarize Astra's recorded synchronous workflow timings from unified logs.

Example:
  log show --last 30m --style compact --predicate 'subsystem == "com.omeriadon.astra"' \
    > /tmp/astra-log.txt
  python3 scripts/astra_workflow_report.py /tmp/astra-log.txt --json
  python3 scripts/astra_workflow_report.py /tmp/baseline.txt --compare /tmp/candidate.txt

The script never exports URLs, tab titles or window identifiers. These are
synchronous stage timings only, not app-ready/first-paint or energy metrics.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

PATTERN = re.compile(
    r"\[ASTRA\]\s+\[(?:WARNING|DEBUG)\]\s+"
    r"\[(?:performance|persistence|webkit)\]\s+"
    r"\[([a-z][a-z0-9.\-]+)\].*?\belapsed_ms=([0-9]+(?:\.[0-9]+)?)\b"
)
STAGES = {
    "workflow.tab.create-to-model-commit": 16,
    "workflow.tabs.close-to-model-commit": 24,
    "tab.select.end": 40,
    "workflow.windows.shared-state-fanout": 30,
    "workflow.webview-hosts.resolve": 8,
    "webview.host.attach": 30,
    "state.snapshot-preparation.end": 16,
    "state.encode.end": 125,
    "state.previous-decode.end": 125,
    "state.commit.end": 125,
    "scroll.save.end": 40,
}


def load(text: str) -> dict[str, list[float]]:
    values: dict[str, list[float]] = defaultdict(list)
    for line in text.splitlines():
        match = PATTERN.search(line)
        if match is None or match.group(1) not in STAGES:
            continue
        duration = float(match.group(2))
        if math.isfinite(duration):
            values[match.group(1)].append(duration)
    return dict(values)


def quantile(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * percentile) - 1)]


def summarize(values: dict[str, list[float]]) -> dict[str, dict[str, float | int | bool]]:
    return {
        stage: {
            "count": len(samples),
            "p50_ms": round(statistics.median(samples), 3),
            "p95_ms": round(quantile(samples, 0.95), 3),
            "max_ms": round(max(samples), 3),
            "budget_ms": STAGES[stage],
            "p95_exceeds_budget": quantile(samples, 0.95) >= STAGES[stage],
        }
        for stage, samples in sorted(values.items()) if samples
    }


def compare(baseline: dict[str, list[float]], candidate: dict[str, list[float]]) -> dict[str, dict]:
    rows = {}
    for stage in sorted(set(baseline) | set(candidate)):
        before, after = baseline.get(stage, []), candidate.get(stage, [])
        # Do not declare performance regressions based on a single user action.
        if len(before) < 5 or len(after) < 5:
            rows[stage] = {"comparable": False, "baseline_samples": len(before), "candidate_samples": len(after)}
            continue
        old, new = statistics.median(before), statistics.median(after)
        rows[stage] = {
            "comparable": True,
            "baseline_samples": len(before),
            "candidate_samples": len(after),
            "baseline_p50_ms": round(old, 3),
            "candidate_p50_ms": round(new, 3),
            "change_pct": round(((new - old) / old) * 100, 2) if old else None,
        }
    return rows


def self_test() -> None:
    raw = "\n".join([
        f"2026-10-09T12:00:00Z [ASTRA] [WARNING] [performance] [workflow.tab.create-to-model-commit] | elapsed_ms={i * 10}.0 tabs_before=50"
        for i in range(1, 11)
    ]) + "\n[ASTRA] [WARNING] [performance] [other.stage] | elapsed_ms=999\n"
    values = load(raw)
    assert len(values) == 1
    summary = summarize(values)["workflow.tab.create-to-model-commit"]
    assert summary["count"] == 10 and summary["p50_ms"] == 55
    assert summary["p95_ms"] == 100 and summary["p95_exceeds_budget"]
    assert compare(values, values)["workflow.tab.create-to-model-commit"]["change_pct"] == 0
    assert compare(values, {})["workflow.tab.create-to-model-commit"]["comparable"] is False
    assert not load("url=https://example.com elapsed_ms=100")
    print("Astra workflow timing analyzer self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logfile", nargs="?", help="macOS unified-log text file; stdin if omitted")
    parser.add_argument("--compare", help="candidate unified-log text file")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    data = Path(args.logfile).read_text(encoding="utf-8", errors="replace") if args.logfile else sys.stdin.read()
    original = load(data)
    result: dict = {"stages": summarize(original), "measurements": sum(map(len, original.values()))}
    if args.compare:
        candidate = load(Path(args.compare).read_text(encoding="utf-8", errors="replace"))
        result["candidate"] = summarize(candidate)
        result["comparison"] = compare(original, candidate)
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        for name, metrics in result["stages"].items():
            print(f"{name:<49} n={metrics['count']:>3} p50={metrics['p50_ms']:>8.1f} ms "
                  f"p95={metrics['p95_ms']:>8.1f} ms max={metrics['max_ms']:>8.1f} ms")
        if args.compare:
            for name, metrics in result["comparison"].items():
                if metrics["comparable"]:
                    print(f"CHANGE {name}: {metrics['change_pct']:+.1f}% median")
                else:
                    print(f"INCOMPARABLE {name}: insufficient observations (<5 per run)")
        if not original:
            print("No matching duration records; Release only emits intervals above the warning threshold.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
