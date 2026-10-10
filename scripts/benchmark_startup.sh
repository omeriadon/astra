#!/usr/bin/env bash
# Repeated, low-disk-usage macOS startup benchmark. Does not reset browser data.
# Usage: bash scripts/benchmark_startup.sh /path/to/astra.app [runs]
# Optional: ASTRA_BENCH_WAIT_SECONDS=8 ASTRA_BENCH_PURGE=1 ...
set -euo pipefail

APP="${1:?Usage: $0 /path/to/astra.app [runs]}"
RUNS="${2:-8}"
WAIT_SECONDS="${ASTRA_BENCH_WAIT_SECONDS:-7}"
PURGE="${ASTRA_BENCH_PURGE:-0}"
OUTPUT="${ASTRA_BENCH_OUTPUT:-$PWD/astra-startup-benchmark.csv}"

[[ -d "$APP" ]] || { echo "App not found: $APP" >&2; exit 1; }
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || { echo "Runs must be a positive integer" >&2; exit 1; }
[[ "$WAIT_SECONDS" =~ ^[1-9][0-9]*$ ]] || { echo "WAIT_SECONDS must be a positive integer" >&2; exit 1; }
command -v log >/dev/null || { echo "macOS log utility missing" >&2; exit 1; }
command -v open >/dev/null || { echo "macOS open utility missing" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 missing" >&2; exit 1; }
if pgrep -x astra >/dev/null; then
  echo "Quit all Astra instances before benchmarking; refusing to reuse a running process." >&2
  exit 1
fi

echo 'run,pid,first_window_ordered_ms,first_appkit_visible_update_ms,all_windows_ordered_ms,session_restoration_complete_ms,deferred_services_scheduled_ms' > "$OUTPUT"
echo "Output: $OUTPUT"

for ((run = 1; run <= RUNS; run++)); do
  if [[ "$PURGE" == "1" ]]; then
    sudo purge || { echo "purge failed; not treating this as a cold-ish run" >&2; exit 1; }
  fi
  open -a "$APP"
  pid=""
  for ((attempt = 0; attempt < 150; attempt++)); do
    pid="$(pgrep -x astra | tail -n 1 || true)"
    [[ -n "$pid" ]] && break
    sleep 0.05
  done
  [[ -n "$pid" ]] || { echo "Astra did not start" >&2; exit 1; }

  sleep "$WAIT_SECONDS"
  capture="$(mktemp)"
  # Predicate limits results to this precise process, avoiding prior runs.
  log show --info --debug --last "$((WAIT_SECONDS + 30))s" \
    --predicate "processID == $pid AND subsystem == 'com.omeriadon.astra' AND category == 'lifecycle'" \
    > "$capture" 2>/dev/null || true

  python3 - "$capture" "$OUTPUT" "$run" "$pid" <<'PY'
import csv
import re
import sys

path, output, run, pid = sys.argv[1:]
names = [
    "startup.first-window-presented",
    "startup.first-visible-window-update",
    "startup.windows-presented",
    "startup.restoration-complete",
    "startup.deferred-services-scheduled",
]
values = {name: "" for name in names}
with open(path, encoding="utf-8", errors="replace") as log:
    for line in log:
        for name in names:
            if f"[{name}]" not in line:
                continue
            match = re.search(r"\belapsed_ms=(\d+(?:\.\d+)?)", line)
            if match:
                values[name] = match.group(1)
with open(output, "a", newline="", encoding="utf-8") as result:
    csv.writer(result).writerow([run, pid, *[values[name] for name in names]])
print(f"Run {run}: first ordered={values[names[0]] or 'missing'} ms; "
      f"first AppKit update={values[names[1]] or 'missing'} ms")
PY
  rm -f "$capture"
  # A graceful quit preserves user sessions and shutdown metadata.
  osascript -e 'tell application id "com.omeriadon.astra" to quit' >/dev/null 2>&1 || true
  for ((attempt = 0; attempt < 150; attempt++)); do
    pgrep -x astra >/dev/null || break
    sleep 0.1
  done
  if pgrep -x astra >/dev/null; then
    echo "Astra did not quit cleanly; aborting rather than force-killing it." >&2
    exit 1
  fi
  sleep 1
done

python3 - "$OUTPUT" <<'PY'
import csv
import math
import statistics
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    rows = list(csv.DictReader(source))
for field in list(rows[0])[2:] if rows else []:
    values = sorted(float(row[field]) for row in rows if row[field])
    if not values:
        print(f"{field}: no samples; check OSLog availability")
        continue
    p95 = values[max(0, math.ceil(0.95 * len(values)) - 1)]
    print(f"{field}: n={len(values)}, median={statistics.median(values):.1f} ms, p95={p95:.1f} ms")
PY
