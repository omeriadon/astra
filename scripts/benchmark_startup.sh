#!/usr/bin/env bash
# Repeated, low-disk-usage macOS startup benchmark. Does not reset browser data.
# Usage: bash scripts/benchmark_startup.sh /path/to/astra.app [runs]
# Optional: ASTRA_BENCH_WAIT_SECONDS=8 ASTRA_BENCH_PURGE=1 ...
set -euo pipefail

command -v python3 >/dev/null || { echo "python3 missing" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="$SCRIPT_DIR/parse_startup_log.py"
[[ -f "$PARSER" ]] || { echo "Startup log parser missing: $PARSER" >&2; exit 1; }
if [[ "${ASTRA_BENCH_SELF_TEST:-0}" == "1" ]]; then
  python3 "$PARSER" --self-test
  command -v clang >/dev/null || { echo "clang missing" >&2; exit 1; }
  helper_dir="$(mktemp -d)"
  trap 'rm -rf "$helper_dir"' EXIT
  clang -O2 "$SCRIPT_DIR/process_birth.c" -o "$helper_dir/process_birth"
  birth="$($helper_dir/process_birth)"
  [[ "$birth" =~ ^[0-9]+\.[0-9]{6}$ ]] || { echo "process birth helper self-test failed" >&2; exit 1; }
  echo "Process birth helper self-test passed"
  exit 0
fi

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
command -v clang >/dev/null || { echo "clang missing" >&2; exit 1; }
if pgrep -x astra >/dev/null; then
  echo "Quit all Astra instances before benchmarking; refusing to reuse a running process." >&2
  exit 1
fi

birth_helper="$(mktemp -d)/process_birth"
trap 'rm -rf "${birth_helper%/*}"' EXIT
clang -O2 "$SCRIPT_DIR/process_birth.c" -o "$birth_helper"
echo 'run,pid,process_birth_to_main_log_ms,process_birth_to_first_window_ms,process_birth_to_first_visible_update_ms,process_birth_to_first_usable_window_ms,process_birth_to_all_windows_ms,process_birth_to_restoration_complete_ms,process_birth_to_deferred_services_ms,first_window_visible,first_window_key,first_window_can_become_key,first_window_hydrated,first_window_first_responder' > "$OUTPUT"
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
  birth="$($birth_helper "$pid")"

  sleep "$WAIT_SECONDS"
  capture="$(mktemp)"
  # Predicate limits results to this precise process, avoiding prior runs.
  log show --style json --info --debug --last "$((WAIT_SECONDS + 30))s" \
    --predicate "processID == $pid AND subsystem == 'com.omeriadon.astra' AND category == 'lifecycle'" \
    > "$capture" 2>/dev/null || true

  parse_status=0
  parsed="$(python3 "$PARSER" "$capture" "$birth" --run "$run" --pid "$pid" --output "$OUTPUT" --require-usable)" || parse_status=$?
  IFS=',' read -r _ _ main first_window first_visible first_usable _ _ _ _ _ _ _ _ <<< "$parsed"
  echo "Run $run: process birth to first main log=${main:-missing} ms; first usable window=${first_usable:-missing} ms; first AppKit update proxy=${first_visible:-missing} ms"
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
  if (( parse_status != 0 )); then
    echo "Run $run failed startup measurement validation" >&2
    exit "$parse_status"
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
timing_fields = [
    "process_birth_to_main_log_ms",
    "process_birth_to_first_window_ms",
    "process_birth_to_first_visible_update_ms",
    "process_birth_to_first_usable_window_ms",
    "process_birth_to_all_windows_ms",
    "process_birth_to_restoration_complete_ms",
    "process_birth_to_deferred_services_ms",
]
for field in timing_fields:
    values = sorted(float(row[field]) for row in rows if row[field])
    if not values:
        print(f"{field}: no samples; check OSLog availability")
        continue
    p95 = values[max(0, math.ceil(0.95 * len(values)) - 1)]
    print(f"{field}: n={len(values)}, median={statistics.median(values):.1f} ms, p95={p95:.1f} ms")
PY
