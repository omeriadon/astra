#!/usr/bin/env bash
# Resolve the Xcode installation on GitHub's macOS runners.
set -euo pipefail
candidates=(
  /Applications/Xcode_27.2_beta_2.app/Contents/Developer
  /Applications/Xcode_27.2_beta.app/Contents/Developer
  /Applications/Xcode_27.2.app/Contents/Developer
  /Applications/Xcode_27.1.app/Contents/Developer
  /Applications/Xcode_27.0.app/Contents/Developer
)
selected=""
for candidate in "${candidates[@]}"; do
  if [[ -d "$candidate" ]]; then
    selected="$candidate"
    break
  fi
done
if [[ -z "$selected" ]] && xcodebuild -version | head -1 | grep -Eq '^Xcode 27([. ]|$)'; then
  selected="$(xcode-select -p)"
fi
if [[ -z "$selected" ]]; then
  echo "::error::No Xcode 27 installation is available"
  exit 1
fi
sudo xcode-select -s "$selected"
xcodebuild -version
