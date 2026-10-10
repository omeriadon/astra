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

# In Debug, Xcode's ENABLE_DEBUG_DYLIB moves the Swift-side framework
# dependencies from the C launcher into astra.debug.dylib. Release typically
# links them directly into astra. Inspect whichever actually contains the code.
CODE_BINARY="$EXE"
if [[ -f "$APP/Contents/MacOS/astra.debug.dylib" ]]; then
  CODE_BINARY="$APP/Contents/MacOS/astra.debug.dylib"
fi

echo "Launcher dependencies:"
otool -L "$EXE"
echo "Browser code dependencies ($CODE_BINARY):"
code_dependencies="$(otool -L "$CODE_BINARY")"
printf '%s\n' "$code_dependencies"
echo "Website-app runtime dependencies:"
runtime_dependencies="$(otool -L "$RUNTIME")"
printf '%s\n' "$runtime_dependencies"
echo "Browser code runtime search paths:"
code_load_commands="$(otool -l "$CODE_BINARY")"
printf '%s\n' "$code_load_commands" | awk '/cmd LC_RPATH/ { flag=1; next } flag && /path / { print; flag=0 }'

# Use string comparison rather than grep -q in a pipe: pipefail would treat
# SIGPIPE from an early grep match as a false failure.
[[ "$code_dependencies" != *"AstraWebsiteAppRuntime.framework"* ]] || {
  echo "Browser code eagerly links website-app-only runtime" >&2
  exit 1
}
[[ "$runtime_dependencies" == *"Sparkle.framework"* ]] || {
  echo "Website-app runtime is missing its Sparkle dependency" >&2
  exit 1
}
[[ "$code_load_commands" == *"@executable_path/../Frameworks"* ]] || {
  echo "Browser code is missing the embedded-framework search path" >&2
  exit 1
}

if [[ "$SIGNATURE_MODE" != "--unsigned" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP"
  codesign --verify --deep --strict --verbose=2 "$SPARKLE"
fi
echo "PASS: Astra launcher, website-app runtime and Sparkle dependencies are consistent."
