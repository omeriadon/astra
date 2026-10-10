#!/usr/bin/env bash
# Usage: bash scripts/audit_sparkle_bundle.sh /path/to/astra.app [--unsigned]
set -euo pipefail
APP="${1:?Usage: $0 /path/to/astra.app [--unsigned]}"
MODE="${2:-signed}"
EXE="$APP/Contents/MacOS/astra"
CODE="$EXE"
[[ ! -f "$APP/Contents/MacOS/astra.debug.dylib" ]] || CODE="$APP/Contents/MacOS/astra.debug.dylib"
WEB="$APP/Contents/Frameworks/AstraWebsiteAppRuntime.framework/Versions/A/AstraWebsiteAppRuntime"
UPDATER="$APP/Contents/Frameworks/AstraUpdaterRuntime.framework/Versions/A/AstraUpdaterRuntime"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for file in "$EXE" "$CODE" "$WEB" "$UPDATER"; do
  [[ -f "$file" ]] || { echo "::error::Missing required Mach-O: $file" >&2; exit 1; }
done
[[ -d "$SPARKLE" ]] || { echo "::error::Sparkle not embedded in Astra: $SPARKLE" >&2; exit 1; }
echo "Browser code dependencies:"
BROWSER_DEPS="$(otool -L "$CODE")"
printf '%s\n' "$BROWSER_DEPS"
echo "Website runtime dependencies:"
WEB_DEPS="$(otool -L "$WEB")"
printf '%s\n' "$WEB_DEPS"
echo "Lazy updater dependencies:"
UPDATER_DEPS="$(otool -L "$UPDATER")"
printf '%s\n' "$UPDATER_DEPS"
[[ "$BROWSER_DEPS" != *"AstraWebsiteAppRuntime.framework"* ]] || {
  echo "::error::Browser still links website-app runtime" >&2; exit 1;
}
[[ "$BROWSER_DEPS" != *"Sparkle.framework"* ]] || {
  echo "::error::Browser still links Sparkle before main()" >&2; exit 1;
}
[[ "$BROWSER_DEPS" != *"AstraUpdaterRuntime.framework"* ]] || {
  echo "::error::Browser links updater instead of dlopen()" >&2; exit 1;
}
[[ "$WEB_DEPS" != *"Sparkle.framework"* ]] || {
  echo "::error::Website-app runtime eagerly links Sparkle" >&2; exit 1;
}
[[ "$UPDATER_DEPS" == *"Sparkle.framework"* ]] || {
  echo "::error::Updater framework does not link Sparkle" >&2; exit 1;
}
if [[ "$MODE" != "--unsigned" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP"
  codesign --verify --deep --strict --verbose=2 "$WEB"
  codesign --verify --deep --strict --verbose=2 "$UPDATER"
  codesign --verify --deep --strict --verbose=2 "$SPARKLE"
fi
echo "PASS: Browser and website apps do not load Sparkle eagerly; updater owns Sparkle."
