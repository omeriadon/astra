#!/usr/bin/env bash
# Select and verify the Xcode 27 / Swift 6.4 toolchain on GitHub-hosted runners.
set -euo pipefail

candidates=(
  /Applications/Xcode_27.2_beta_2.app/Contents/Developer
  /Applications/Xcode_27.2.app/Contents/Developer
  /Applications/Xcode_27.2_beta.app/Contents/Developer
  /Applications/Xcode_27.1.app/Contents/Developer
  /Applications/Xcode_27.0.app/Contents/Developer
  /Applications/Xcode_27.app/Contents/Developer
)
selected=""
for candidate in "${candidates[@]}"; do
  if [[ -d "$candidate" ]]; then
    selected="$candidate"
    break
  fi
done
if [[ -z "$selected" ]] && xcodebuild -version | head -n 1 | grep -Eq '^Xcode 27([. ]|$)'; then
  selected="$(xcode-select -p)"
fi
if [[ -z "$selected" ]]; then
  echo "::error::Xcode 27 is not installed on this runner"
  exit 1
fi

sudo xcode-select -s "$selected"
xcode_version="$(xcodebuild -version)"
printf '%s\n' "$xcode_version"
if ! printf '%s\n' "$xcode_version" | head -n 1 | grep -Eq '^Xcode 27([. ]|$)'; then
  echo "::error::Expected Xcode 27"
  exit 1
fi

swift_version="$(xcrun swiftc -version)"
printf '%s\n' "$swift_version"
if ! printf '%s\n' "$swift_version" | grep -Eq '^Apple Swift version 6\.4([. ]|$)'; then
  echo "::error::Expected Apple Swift compiler 6.4 from Xcode 27"
  exit 1
fi
