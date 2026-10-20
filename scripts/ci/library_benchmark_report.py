#!/usr/bin/env python3
"""Compare the existing library-scaling benchmark on the same runner.

Timing changes are informational; malformed results are an error.
"""
import argparse
import json
import math
import re
from pathlib import Path

PATTERN = re.compile(
    r"bookmarks=(\d+)\s+reading=(\d+)\s+"
    r"projection_median_ms=([0-9.]+)\s+projection_p95_ms=([0-9.]+)"
)
EXPECTED = {1000, 10000, 50000}


def parse(raw):
    result = {}
    for line in raw.splitlines():
        match = PATTERN.search(line)
        if not match:
            continue
        size, reading, median, p95 = match.groups()
        size = int(size)
        if size in result or any(not math.isfinite(float(x)) for x in (median, p95)):
            raise ValueError("Duplicate or non-finite benchmark measurement")
        result[size] = (int(reading), float(median), float(p95))
    if set(result) != EXPECTED:
        raise ValueError("Missing bookmark measurements: " + str(sorted(EXPECTED - set(result))))
    return result


def compare(before, after):
    rows = []
    for size in sorted(EXPECTED):
        first, second = before[size], after[size]
        if first[0] != second[0]:
            raise ValueError("Cannot compare different workloads")
        pct = round(100 * (second[1] / first[1] - 1), 1) if first[1] > 0 else None
        rows.append({
            "bookmarks": size,
            "baseline_median_ms": first[1],
            "candidate_median_ms": second[1],
            "change_pct": pct,
            "baseline_p95_ms": first[2],
            "candidate_p95_ms": second[2],
        })
    return rows


def report(rows):
    lines = [
        "## Astra library scaling (informational)", "",
        "Same macOS runner, optimised Swift builds; seven measurements per size.",
        "No hard performance threshold is applied.", "",
        "| Bookmarks | Base median | Candidate median | Change | Base p95 | Candidate p95 |",
        "|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        change = "n/a" if row["change_pct"] is None else f"{row['change_pct']:+.1f}%"
        lines.append(
            f"| {row['bookmarks']:,} | {row['baseline_median_ms']:.2f} ms | "
            f"{row['candidate_median_ms']:.2f} ms | {change} | "
            f"{row['baseline_p95_ms']:.2f} ms | {row['candidate_p95_ms']:.2f} ms |"
        )
    lines += ["", "Shared runner hardware, thermal state and scheduling introduce timing noise."]
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--baseline")
    ap.add_argument("--candidate")
    ap.add_argument("--output-dir")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        fixture = "\n".join(
            f"bookmarks={size} reading={size // 10} projection_median_ms=1.5 projection_p95_ms=2.5"
            for size in sorted(EXPECTED)
        )
        assert all(row["change_pct"] == 0 for row in compare(parse(fixture), parse(fixture)))
        try:
            parse("bookmarks=1000 reading=100 projection_median_ms=1 projection_p95_ms=2")
        except ValueError:
            pass
        else:
            raise AssertionError("Incomplete benchmark output was accepted")
        print("Library report self-test passed")
        return
    if not all((args.baseline, args.candidate, args.output_dir)):
        ap.error("--baseline, --candidate and --output-dir are required")
    rows = compare(parse(Path(args.baseline).read_text()), parse(Path(args.candidate).read_text()))
    dest = Path(args.output_dir)
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "library-comparison.json").write_text(json.dumps(rows, indent=2) + "\n")
    summary = report(rows)
    (dest / "library-summary.md").write_text(summary)
    print(summary)


if __name__ == "__main__":
    main()
