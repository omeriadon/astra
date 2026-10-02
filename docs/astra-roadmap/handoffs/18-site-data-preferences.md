# 18-site-data-preferences

Task / selected optional scope: Packet18. Implemented last-hour/today/all-time WebKit storage clearing; WebKit grouped-record removal; synchronized per-origin zoom; device-only per-origin content mode and custom UA; existing per-origin popup permission integration. Per-origin autoplay, reader/site appearance, blocker exceptions, and tracking-parameter stripping remain gated or optional.

Branch / worktree / baseline commit: `astra/roadmap/18-site-data-preferences`, `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/18-site-data-preferences`, baseline `abffc0e`.

Status: source complete, independently reviewed, exact18 Mac build verified. Native website-data removal and interactive site preference behavior remain runtime acceptance cases.

Commit(s): model checkpoint `69288e6`; IPv6 canonicalization checkpoint `aa53150`; implementation checkpoint `6707966fe1ca406410c3783b288abee56490df99`.

Changed files and behavior:

- `BrowserSitePreferenceModel.swift` adds canonical HTTP(S) origin normalization, including equivalent IPv6 spelling normalization, WebKit date-range thresholds, versioned portable zoom records with per-origin timestamps/tombstones and deterministic merge rules, and versioned local-only browsing preferences.
- `BrowserSitePreferences.swift` stores normal site preferences locally, keeps private preferences in session memory, preserves unreadable/future documents, synchronizes portable zoom through the timestamped setting cache, and applies updates to committed same-session controllers.
- `BrowserWebSession.swift` owns the correct preference service and adds session-store time-range and grouped-record clearing. Clearing WebKit data also clears Astra's favicon cache; favicon timestamps are not persisted, so all icons are removed for every requested range.
- `BrowserController.swift` applies site zoom on committed HTTP(S) origins, falls back to Default Page Zoom for an unconfigured destination, and retains restored per-tab zoom only when the actual committed origin matches the restored origin. Provisional, redirected, and failed pages do not receive stale site preferences. Content mode and custom UA apply to the next main-frame navigation without a reload. The existing Chrome Web Store UA exception remains and is marked for review on Chrome major updates.
- `BrowserSyncDocument.swift` merges supported per-origin zoom entries even when outer setting timestamps tie. Unreadable/future site-zoom data stays opaque and retains its current timestamp; unrelated tabs/history/settings still merge. `BrowserDefaults.swift` registers only site zoom as portable. Content mode and custom UA remain device-only because they affect device layout and compatibility behavior. Popup decisions reuse the existing device-only `BrowserSitePermissions` store.
- Privacy settings disclose WebKit record-modification-date limits, grouped domain labels, wholesale favicon deletion, and separation from history and website permissions. Website history/backups are not changed by storage clearing. The existing separate permission-reset controls remain intact.
- `BrowserSitePermissions.origin(for:)` delegates to the shared canonical origin helper, so permission and preference keys use the same origin representation.

Acceptance cases satisfied, with evidence:

- The production check covers canonical origin/default-port/IPv6 normalization, HTTP(S)-only acceptance, last-hour/today/all-time thresholds, legacy version defaults, future/corrupt preservation, per-origin merge, reset tombstones, deterministic equal-time ties, and future timestamp rejection.
- The same runnable check constructs real `BrowserSyncDocument` values. A future opaque local zoom setting and an invalid-inner-timestamp remote zoom value each preserve the current setting and timestamp while remote tabs/history still merge. Two supported disjoint-origin zoom maps with equal outer timestamps merge deterministically in both document orders.
- Browser-level source application applies site zoom only after commit, synchronizes current same-origin controllers/peeks, applies mode/UA only on later main-frame navigations, and preserves restored per-tab zoom only for the restored canonical origin.
- The privacy UI prevents overlapping clears, refreshes website records with a generation guard, and states that WebKit cannot guarantee exact cookie/origin/date deletion.

Checks run:

- Production helper and sync model check passed: `swiftc astra/Models/Spaces/BrowserTheme.swift astra/Models/Tabs/BrowserScrollPosition.swift astra/Models/Tabs/OpenPeek.swift astra/Models/Tabs/OpenTab.swift astra/Models/Tabs/BrowserVisit.swift astra/Models/Library/Bookmark.swift astra/Models/Spaces/BrowserSpace.swift astra/Models/Spaces/BrowserWorkspace.swift astra/Models/Core/BrowserSnapshot.swift astra/Web/Navigation/BrowserSitePreferenceModel.swift astra/Models/Core/BrowserSyncDocument.swift docs/astra-roadmap/checks-18-site-data-preferences.swift -o /tmp/astra-site-preferences-sync-check && /tmp/astra-site-preferences-sync-check`.
- Swift frontend parse passed across the nine changed production Swift files.
- `git diff --check` passed.
- Xcode MCP workspace `workspace-Pt8kjjlln7`, project `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/18-site-data-preferences/astra.xcodeproj`, scheme `astra`, destination `My Mac`: build passed in7.528s with zero errors. Diagnostics reported zero issues in all nine changed production Swift files. Only this task workspace was closed.
- Independent readonly review passed; it reran the production `BrowserSyncDocument` check and confirmed the future-value and equal-time merge behavior.

Checks written but not executed: none. The check ran as a standalone production-model executable; no hosted test target was run.

Pending runtime/provider cases: exercise WebKit's actual modified-since behavior for each data type, the grouped site names/delete path, favicon clearing, login/storage effects in open web views, committed-origin zoom inheritance/restoration, and next-navigation desktop/mobile/UA behavior on macOS and iOS. No app was launched.

Migration, compatibility and private-data impact: newly introduced zoom/local preference documents default to version1 when the version field is absent and use deterministic distant-past age for missing zoom-entry timestamps. Unknown fields, unreadable bytes, and future versions are left in UserDefaults and disable editing for the affected preference type. No existing per-site data key required migration. Private sessions use separate nonpersistent WebKit stores and memory-only site preferences; no private site preference enters normal defaults or sync. Local-only mode/UA values are excluded from the portable setting registry. Existing Chrome Web Store UA behavior remains unchanged unless a per-site UA is explicitly saved.

Capability gates / unresolved issues: WebKit selects all-time/relative website deletion by record modification time, not exact cookie/origin event time. `WKWebsiteDataRecord.displayName` is a grouped domain label. Favicon modification times are not persisted, so selected-range clearing removes all Astra favicons. History and recoverable history backups remain unchanged. `mediaTypesRequiringUserActionForPlayback` is configured per web view, so per-origin autoplay would require replacing a live page and remains unsupported. Site reader/appearance behavior is outside current public site preference controls. Content exceptions depend on packet21's blocker implementation. Tracking-parameter stripping remains optional. No runtime or iOS acceptance was performed.

Merge prerequisites / follow-up ownership: start packet20 from exact packet18 implementation checkpoint `6707966fe1ca406410c3783b288abee56490df99`; preserve the independent packet25 worktree and the original checkout. User-controlled integration only.
