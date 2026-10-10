#!/usr/bin/env bash
# Usage: bash scripts/audit_sparkle_bundle.sh /path/to/astra.app [--unsigned]
# --unsigned is for GitHub Actions' CODE_SIGNING_ALLOWED=NO Debug builds only.
set -euo pipefail

APP="${1:?Usage: $0 /path/to/astra.app [--unsigned]}"
SIGNATURE_MODE="${2:-signed}"
EXE="$APP/Contents/MacOS/astra"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"

[[ -f "$EXE" ]] || { echo "Missing Astra executable: $EXE" >&2; exit 1; }
[[ -d "$SPARKLE" ]] || { echo "Sparkle not embedded at $SPARKLE" >&2; exit 1; }

echo "Direct executable dynamic-library dependencies:"
otool -L "$EXE"

echo
echo "Executable runpaths:"
otool -l "$EXE" | awk '
  /cmd LC_RPATH/ { rpath=1; next }
  rpath && /path / { print; rpath=0 }
'

if ! otool -L "$EXE" | grep -q 'Sparkle.framework'; then
  echo "Expected Sparkle dynamic dependency missing from main executable" >&2
  exit 1
fi

if ! otool -l "$EXE" | grep -q '@executable_path/../Frameworks'; then
  echo "Missing @executable_path/../Frameworks runtime search path" >&2
  exit 1
fi

echo
echo "Embedded Sparkle framework:"
ls -ld "$SPARKLE" "$SPARKLE/Versions/Current" || true

if [[ "$SIGNATURE_MODE" != "--unsigned" ]]; then
  echo
  echo "Verifying release bundle and nested framework signatures:"
  codesign --verify --deep --strict --verbose=2 "$APP"
  codesign --verify --deep --strict --verbose=2 "$SPARKLE"
  codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Identifier=|Authority=|TeamIdentifier=' || true
fi

echo "PASS: Sparkle is embedded and accessible through the executable runpath."
