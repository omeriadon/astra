#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Real Astra Browser Use E2E requires macOS.' >&2
  exit 2
fi
APP=${1:?Supply a built Debug astra.app path}
APP=$(cd "$APP" && pwd -P)
[[ -d "$APP/Contents/MacOS" ]] || { echo 'Expected a macOS app bundle' >&2; exit 2; }
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/astra-mcp-e2e.XXXXXXXX")
SITE_PID=''
# Preserve non-sensitive reports on failure when CI supplies this directory.
REPORT_DIR=${ASTRA_BROWSER_USE_REPORT_DIR:-}
ASTRA_PID=''
cleanup() {
  [[ -z "$ASTRA_PID" ]] || { kill "$ASTRA_PID" 2>/dev/null || :; wait "$ASTRA_PID" 2>/dev/null || :; }
  [[ -z "$SITE_PID" ]] || { kill "$SITE_PID" 2>/dev/null || :; wait "$SITE_PID" 2>/dev/null || :; }
  if [[ -n "$REPORT_DIR" ]]; then
    mkdir -p "$REPORT_DIR"
    cp "$TMP/site.log" "$TMP/app.log" "$TMP/client.log" "$REPORT_DIR/" 2>/dev/null || :
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT INT TERM
mkdir -p "$TMP/app"
ditto "$APP" "$TMP/app/astra.app"
RUN_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
PROFILE="com.omeriadon.astra.mcp-test.$RUN_ID"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $PROFILE" "$TMP/app/astra.app/Contents/Info.plist"
# Debug-only ad-hoc signature applies to the copy, never the developer's app.
codesign --force --deep --sign - "$TMP/app/astra.app"
echo 'Starting deterministic Browser Use HTTP fixture...'
python3 "$ROOT/scripts/browser-use/site/server.py" --ready-file "$TMP/site.json" >"$TMP/site.log" 2>&1 &
SITE_PID=$!
# A heavily loaded macOS CI runner can take longer than 5 seconds to start
# Python and bind both fixture listeners. Never start Astra before readiness.
for ((i=0;i<300;i++)); do
  [[ -s "$TMP/site.json" ]] && break
  if ! kill -0 "$SITE_PID" 2>/dev/null; then
    echo 'Browser Use HTTP fixture exited before publishing its readiness file.' >&2
    cat "$TMP/site.log" >&2
    exit 1
  fi
  sleep .1
done
if [[ ! -s "$TMP/site.json" ]]; then
  echo 'Browser Use HTTP fixture did not become ready within 30 seconds.' >&2
  ps -p "$SITE_PID" -o pid=,stat=,command= >&2 || :
  tail -80 "$TMP/site.log" >&2 || :
  exit 1
fi
echo 'Browser Use HTTP fixture ready.'
UPLOAD_SCOPE=$(uuidgen)
python3 - "$TMP/astra-upload-fixture.bin" <<'PYUPLOAD'
import sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(bytes(range(256))*64)
PYUPLOAD
ASTRA_BROWSER_USE_UPLOAD_SCOPE="$UPLOAD_SCOPE" ASTRA_BROWSER_USE_UPLOAD_FILE="$TMP/astra-upload-fixture.bin" ASTRA_BROWSER_USE_TEST=1 ASTRA_BROWSER_USE_HANDSHAKE="$TMP/handshake.json" \
  ASTRA_BROWSER_USE_RUN_ID="$RUN_ID" "$TMP/app/astra.app/Contents/MacOS/astra" >"$TMP/app.log" 2>&1 &
ASTRA_PID=$!
for ((i=0;i<300;i++)); do
  [[ -s "$TMP/handshake.json" ]] && break
  kill -0 "$ASTRA_PID" 2>/dev/null || break
  sleep .1
done
if [[ ! -s "$TMP/handshake.json" ]]; then
  echo 'Astra did not publish an authenticated test handshake:' >&2
  tail -80 "$TMP/app.log" >&2
  exit 1
fi
python3 "$ROOT/scripts/browser-use/client/run.py" --handshake "$TMP/handshake.json" \
  --site "$TMP/site.json" --run "$RUN_ID" --profile "$PROFILE" --pid "$ASTRA_PID" \
  --upload-scope "$UPLOAD_SCOPE" 2>&1 | tee "$TMP/client.log"
