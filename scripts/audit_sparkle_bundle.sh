#!/usr/bin/env bash
# Usage: bash scripts/audit_sparkle_bundle.sh /path/to/astra.app [--unsigned]
# Unsigned mode is only for CI builds with signing disabled.
set -euo pipefail

APP="${1:?Usage: $0 /path/to/astra.app [--unsigned]}"
SIGNATURE_MODE="${2:-signed}"
EXE="$APP/Contents/MacOS/astra"
RUNTIME="$APP/Contents/Frameworks/AstraWebsiteAppRuntime.framework/Versions/A/AstraWebsiteAppRuntime"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"

[[ -f "$EXE" ]] || { echo "Missing executable: $EXE" >&2; exit 1; }
[[ -f "$RUNTIME" ]] || { echo "Missing website app runtime: $RUNTIME" >&2; exit 1; }
[[ -d "$SPARKLE" ]] || { echo "Sparkle not embedded: $SPARKLE" >&2; exit 1; }

echo "Main executable dependencies:"
otool -L "$EXE"
echo "Website-app runtime dependencies:"
otool -L "$RUNTIME"
echo "Runtime search paths:"
otool -l "$EXE" | awk '/cmd LC_RPATH/ { flag=1; next } flag && /path / { print; flag=0 }'

# AstraAppLauncher is a small C binary. Its browser entry point lives inside
# the website-app runtime; Sparkle itself is linked by that runtime.
otool -L "$EXE" | grep -q 'AstraWebsiteAppRuntime.framework' || {
  echo "Astra's browser entry point is not linked from the embedded runtime" >&2
  exit 1
}
otool -L "$RUNTIME" | grep -q 'Sparkle.framework' || {
  echo "Website-app runtime is missing its Sparkle dependency" >&2
  exit 1
}
otool -l "$EXE" | grep -q '@executable_path/../Frameworks' || {
  echo "Astra's executable is missing its embedded-framework runpath" >&2
  exit 1
}

if [[ "$SIGNATURE_MODE" != "--unsigned" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP"
  codesign --verify --deep --strict --verbose=2 "$SPARKLE"
fi
echo "PASS: Astra launcher, website-app runtime and Sparkle dependencies are consistent."
