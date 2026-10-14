#!/bin/bash
# Capture matched foreground/background sync runs on an already running macOS app.
set -euo pipefail
if [[ $# -ne 3 ]]; then
  echo 'Usage: profile_sync.sh PID SECONDS OUTPUT_DIRECTORY' >&2
  exit 2
fi
sync_pid="$1"
sync_seconds="$2"
sync_output="$3"
[[ "$sync_pid" =~ ^[0-9]+$ && "$sync_seconds" =~ ^[0-9]+$ && "$sync_seconds" -gt 0 ]]
kill -0 "$sync_pid"
mkdir -p "$sync_output"
if [[ -e "$sync_output/time-profiler.trace" ]]; then
  echo 'Output already contains a trace; use a fresh directory.' >&2
  exit 2
fi
sw_vers > "$sync_output/system.txt"
pmset -g custom > "$sync_output/power.txt"
log stream --style compact --level info \
  --predicate 'subsystem == "com.omeriadon.astra" AND (category == "sync" OR category == "persistence")' \
  > "$sync_output/events.log" 2>&1 &
sync_log_pid=$!
sync_sampler_pid=''
cleanup() {
  kill "$sync_log_pid" 2>/dev/null || true
  if [[ -n "$sync_sampler_pid" ]]; then kill "$sync_sampler_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM
(
  echo 'timestamp,pid,cpu_percent,memory_percent,resident_kib'
  for ((sync_index=0; sync_index<sync_seconds; sync_index++)); do
    sync_sample=$(ps -p "$sync_pid" -o pid=,%cpu=,%mem=,rss=)
    [[ -n "$sync_sample" ]] || break
    echo "$sync_sample" | awk -v stamp="$(date -u +%FT%TZ)" '{print stamp "," $1 "," $2 "," $3 "," $4}'
    sleep 1
  done
) > "$sync_output/process.csv" &
sync_sampler_pid=$!
xcrun xctrace record --template 'Time Profiler' --attach "$sync_pid" \
  --time-limit "${sync_seconds}s" --output "$sync_output/time-profiler.trace"
wait "$sync_sampler_pid"
