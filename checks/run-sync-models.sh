#!/usr/bin/env bash
# macOS / Xcode 27: actual sync models and persistence, without app/network dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v swiftc >/dev/null || { echo 'Swift compiler required (Xcode 27)'; exit 1; }
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
# Extract ancillary production value declarations from files also containing live
# AI services. No sync, merge, URL, encoding, or persistence implementation is mocked.
python3 - "$work_dir" <<'PY'
import pathlib, sys
out = pathlib.Path(sys.argv[1])
def declaration(path, marker):
    text = pathlib.Path(path).read_text()
    start = text.index(marker)
    opening = text.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]
monitor = declaration('astra/AI/BrowserWebsiteMonitoring.swift', 'nonisolated struct BrowserMonitorMatch:')
group = declaration('astra/AI/Features/BrowserPageFeatures.swift', 'nonisolated struct Group:')
sync_error = declaration('astra/Storage/BrowserSync.swift', 'nonisolated enum BrowserSyncError:')
import_error = declaration('astra/Storage/BrowserUserData.swift', 'enum ImportError:')
(out / 'AncillaryValues.swift').write_text('import Foundation\n' + monitor + '\n' + sync_error + '\nenum BrowserTabGroupingFeature {\n' + group + '\n}\nenum BrowserUserData {\n' + import_error + '\n}\n')
# Give the previous snippet its own executable entry point.
projection = pathlib.Path('checks/sync-projection-check.swift').read_text()
(out / 'ProjectionCheck.swift').write_text('import Foundation\n@main struct ProjectionCheck { static func main() throws {\n' + projection + '\n}}\n')
PY
sources=(
  astra/Models/Spaces/BrowserTheme.swift
  astra/Models/Spaces/BrowserSpace.swift
  astra/Models/Spaces/BrowserWorkspace.swift
  astra/Models/Tabs/BrowserScrollPosition.swift
  astra/Models/Tabs/OpenTab.swift
  astra/Models/Tabs/OpenPeek.swift
  astra/Models/Tabs/BrowserEasel.swift
  astra/Models/Tabs/BrowserVisit.swift
  astra/Models/Library/Bookmark.swift
  astra/Models/Library/BrowserBoost.swift
  astra/Models/Core/BrowserSnapshot.swift
  astra/Models/Core/BrowserSyncDocument.swift
  astra/Web/Navigation/BrowserSitePreferenceModel.swift
  astra/Storage/BrowserSyncEngine.swift
  astra/Storage/BrowserSyncPayloadLimits.swift
  astra/Storage/BrowserPersistence.swift
  astra/App/BrowserLog.swift
  "$work_dir/AncillaryValues.swift"
)
# Keep assertions enabled: existing integration fixtures deliberately use assert.
for fixture in docs/astra-roadmap/checks-29-sync-models.swift docs/astra-roadmap/checks-03-persistence.swift "$work_dir/ProjectionCheck.swift" checks/sync-engine-check.swift; do
  swiftc -swift-version 6 -default-isolation MainActor -Onone "${sources[@]}" "$fixture" -o "$work_dir/check"
  "$work_dir/check"
done
swiftc -swift-version 6 -default-isolation MainActor -O "${sources[@]}" checks/sync-document-benchmark.swift -o "$work_dir/benchmark"
"$work_dir/benchmark"
