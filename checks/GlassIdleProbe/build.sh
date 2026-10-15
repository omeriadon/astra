#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OUTPUT="/Users/omeriadon/Desktop/astra-render-investigation-20261014/GlassIdleProbe.app"
CONTENTS="$OUTPUT/Contents"
MACOS="$CONTENTS/MacOS"

mkdir -p "$MACOS"
swiftc "$ROOT/main.swift" "$ROOT/AppDelegate.swift" "$ROOT/ProbeMode.swift" "$ROOT/LifecycleLogger.swift" "$ROOT/GlassIdleProbeView.swift" "$ROOT/WindowVisibilityReader.swift" "$ROOT/VisibilityPredicate.swift" \
    -o "$MACOS/GlassIdleProbe" \
    -target arm64-apple-macosx27.0 \
    -swift-version 6 \
    -O \
    -framework AppKit \
    -framework SwiftUI \
    -parse-as-library

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
swiftc "$ROOT/ProbeMode.swift" "$ROOT/VisibilityPredicate.swift" "$ROOT/VisibilitySelfCheck.swift" -swift-version 6 -o /tmp/GlassIdleProbe-visibility-self-check
/tmp/GlassIdleProbe-visibility-self-check
echo "$OUTPUT"
