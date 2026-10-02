# 16 Chrome, find and zoom

Task / selected optional scope: `16-chrome-find-zoom`; native WebKit find and bounded tab zoom. No optional scope.

Branch / worktree / baseline commit: `astra/roadmap/16-chrome-find-zoom` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/16-chrome-find-zoom` / `6f3132c`.

Status: source complete; primary Xcode review/build and runtime acceptance pending.

Commit(s), or explicit uncommitted state: `2598935` (`implement browser find and page zoom`), `6187f1a` (`record browser chrome find zoom handoff`), and `1963887` (`fix chrome zoom freshness and find races`). The correction checkpoint includes the updated handoff and production check.

Changed files and behavior:

- `astra/Web/Navigation/BrowserController.swift` rejects delayed native find results after query, document generation, WebView, or controller ownership changes. It does not start find while navigation awaits commit; the current query is searched after the same live navigation finishes. Find state is unknown while pending and shows “No matches” only after WebKit reports no match. `WKFindResult` exposes only `matchFound`; Astra does not fabricate a total or current match number. Zoom writes are clamped at the controller boundary, including extension and WebKit paths, and menu/page controls share the same bounds. Only an actual zoom value change invokes `zoomDidChange`.
- `astra/Web/Navigation/BrowserZoomPolicy.swift` provides finite 25%–500% zoom bounds, the 100% default, the production find-generation token, and the find-navigation admission check.
- `astra/Models/Tabs/BrowserTab.swift` reads the portable default only when a tab has no explicitly restored zoom. Existing per-tab `OpenTab.pageZoom` restoration remains authoritative. The controller's dedicated zoom callback invalidates the cached open-tab snapshot and stamps actual edits for normal tabs and peeks. It suppresses sync-application callbacks; constructor and wake restoration happen before observation is attached, and unloaded tabs retain their stored value.
- `astra/UI/Chrome/BrowserNavigationControls.swift` adds accessible zoom-out, reset/percentage and zoom-in controls to the selected active controller's existing navigation controls. `BrowserPageView.swift` and `BrowserLoadingBar.swift` already render against `activeController`, including peeks; their routing needed no edits.
- `astra/UI/Chrome/BrowserFindBar.swift` refreshes native results when shown and invalidates pending results when its controller leaves the selected chrome. `BrowserPageView` keys the bar by controller identity so a switch resets focus and disposes the prior controller's view. Existing next, previous, close, Escape and no-match behavior remains native.
- `astra/UI/AddressBar/BrowserAddressField.swift` refreshes for active-controller, display-style and search-configuration changes only when the field is not being edited. Loading/progress changes do not write its text, and selection changes do not replace in-progress text.
- `astra/Storage/BrowserDefaults.swift`, `astra/UI/Settings/Detail/BrowserGeneralSettingsView.swift`, and `astra/UI/Settings/BrowserSettingsView.swift` add a 25%–500% default zoom slider, reset control and settings-search terms. `defaultPageZoom` is registered in the existing timestamped synced-settings mechanism.
- `docs/astra-roadmap/checks/task16-chrome-find-zoom.swift` runs finite/bounds and stale-generation assertions.

Acceptance cases satisfied, with evidence:

- Selected address and navigation chrome use `selectedTab.activeController`; BrowserPageView and the loading bar already use this owner. The address field now observes active-controller identity and protects focused edits.
- Native search uses `WKWebView.find` and `WKFindResult.matchFound`. The result callback checks the captured query, request generation, same live WebView and controller ownership. Query changes, provisional navigation, browser navigation and close invalidate older requests.
- Zoom is bounded to the existing persistence/sync contract range. The visible percentage reads controller state; reset returns to 100%. Default zoom is applied only when constructing a fresh tab without restored zoom.
- Zoom persistence callbacks run only for actual normalized value changes. Normal tabs and peeks invalidate `OpenTab` caches and update freshness. Sync application is guarded, and restored controller values are applied before callbacks are attached; hibernated tabs retain their stored zoom.
- Find is admitted only when navigation is not awaiting commit. `didFinish` reissues the open bar's current query only for the controller's current navigation.

Checks run, scheme/destination/workspace and results:

- `swiftc -frontend -parse` over every changed production Swift source and the task check — passed. This confirms parsing only, not Xcode type checking.
- `swiftc astra/Web/Navigation/BrowserZoomPolicy.swift docs/astra-roadmap/checks/task16-chrome-find-zoom.swift -o /tmp/task16-chrome-find-zoom-check && /tmp/task16-chrome-find-zoom-check` — passed: `Task 16 chrome/find/zoom checks passed`; includes unchanged/changed zoom notification, find admission and stale-generation cases.
- `git diff --check` — passed after the correction.
- No Xcode MCP workspace/build was opened; serialized Xcode verification belongs to the primary. No app or hosted test target was launched.

Checks written but not executed: no hosted UI/WebKit check. The task-owned production policy check above was executed.

Pending runtime/hardware/provider cases: native selection/highlight behavior and query timing for supported macOS/iOS WebKit; close/reset highlight behavior; focus restoration; navigation races; active peek/PiP source selection; accessibility rendering of the compact percentage control; iOS target type checking. No runtime acceptance is claimed.

Migration, compatibility and private-data impact: no persistence or sync document schema change. Existing tab zoom fields retain their format and explicit saved values win over the new fresh-tab default. `defaultPageZoom` is portable and timestamped by `BrowserSync`'s existing settings registry; sync initialization/merge already assigns timestamps only for actual changed settings, and the slider uses the existing defaults mechanism. No private data or website content is read or stored.

Capability gates / unresolved issues: public `WKFindResult` only reports whether any match exists, so count and current-index presentation remain unavailable. Xcode type checking, supported-device behavior and visual accessibility review remain pending.

Merge prerequisites / follow-up ownership: primary source review and serialized Mac build. Task 18 can attach per-site rules at the existing `BrowserTab`/controller `pageZoom` owner; it must define precedence over the already-existing per-tab value and fresh-tab default. Preserve the count-unavailable limitation and explicit restored zoom precedence.
