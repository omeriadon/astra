# Task 06: failures and offline recovery

Task / selected optional scope: DNS, offline, reset, TLS, unsupported URL, redirect-loop, and WebContent termination presentation; request-preserving retry; connectivity-return retry for safe methods.
Branch / worktree / baseline commit: `astra/roadmap/06-failures-offline` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/06-failures-offline` / `044a925169865760f1913c1b7d78a6ef4b21b415`.
Status: source complete; macOS build verified; iOS simulator build blocked by unresolved existing Sparkle package dependency.
Commit(s), or explicit uncommitted state: `4cf7453` (`handle navigation failures and offline recovery`); `dbc7a33` (`bound offline retries and crash recovery`). This handoff records the build for `dbc7a33`.

Changed files and behavior:

- `BrowserController.swift` retains the active main-frame request for explicit retry, ignores canceled and stale navigation failures through its existing navigation guard, retries one offline/connection-lost GET or HEAD after connectivity returns, and resets that allowance for a new accepted link, form, back/forward, reload, or address-bar navigation. Teardown unregisters connectivity observation and releases pending/current/failed requests; the shared load boundary rejects invalidated controllers.
- `BrowserNavigationFailure.swift` maps App Transport Security failures, models repeated process termination, and owns the body-free GET/HEAD retry eligibility rule. Same-URL crashes remain repeated across reload commits; a committed different URL or 60 seconds without another crash resets the tracker.
- `BrowserNavigationConnectivity.swift` uses one native `NWPathMonitor` to publish connectivity changes. It does not alter WebKit networking or the sync monitor.
- `BrowserNavigationErrorView.swift` reports connectivity recovery on offline error pages and retains its accessible refresh control.
- `checks/failures-offline/main.swift` checks production classification and automatic retry eligibility.

Acceptance cases satisfied, with evidence: source inspection confirms only current `WKNavigation` failures are applied; cancellation and download handoff remain separate; retry retains the original request; invalidated controllers cannot load after close; automatic retries require body-free GET/HEAD and happen at most once per eligible failure; new native navigation restores the allowance; repeated same-URL content-process failures survive reload commits and stop after a different committed URL or 60 seconds. Foundation-only production-helper assertions passed.
Checks run, scheme/destination/workspace and results: Foundation-only production-helper executable and `git diff --check` passed. Xcode workspace `workspace-sytSFUtiVt`, scheme `astra`: macOS `My Mac` build succeeded (log `/var/folders/s_/ms68q0zx137_d7r08rxtnp9w0000gq/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261001-124441.txt`); changed Swift source diagnostics reported no issues. iOS simulator `iPhone 17e` build failed because Xcode could not resolve the existing `Sparkle` module imported by `astra/UI/Settings/Detail/Update/BrowserUpdateSheet.swift` (log `/var/folders/s_/ms68q0zx137_d7r08rxtnp9w0000gq/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261001-124509.txt`). The active destination was restored to `My Mac`.
Checks written but not executed: none beyond the source-compiled Foundation-only assertion executable.
Pending runtime/hardware/provider cases: real offline-to-online transition; DNS/reset/TLS/redirect errors; repeated WebContent termination; service-worker offline responses; GET/HEAD auto retry and POST/form/upload non-replay in WebKit. iOS app compilation also remains pending until Xcode resolves Sparkle.
Migration, compatibility and private-data impact: none. Failed request data remains in controller memory only. Existing diagnostics expose failure kind without URL, headers, body, or page content. Normal/private session boundaries are unchanged.
Capability gates / unresolved issues: runtime behavior of `NWPathMonitor` remains unverified. The iOS build is blocked by the unresolved Sparkle dependency reported above.
Merge prerequisites / follow-up ownership: task 02 is present in baseline. Primary review remains pending.

Primary review added early invalidation guards to the public load/navigate entry points as well as the shared request-loading boundary. This prevents a stale closed controller from reaching external-app handoff or recreating a view before the lower-level load guard. The existing macOS build predates these two guards; source inspection verifies they use the existing lifecycle flag, and the final combined build will compile them.
