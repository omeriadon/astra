# Task 06: failures and offline recovery

Task / selected optional scope: DNS, offline, reset, TLS, unsupported URL, redirect-loop, and WebContent termination presentation; request-preserving retry; connectivity-return retry for safe methods.
Branch / worktree / baseline commit: `astra/roadmap/06-failures-offline` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/06-failures-offline` / `044a925169865760f1913c1b7d78a6ef4b21b415`.
Status: source complete; Xcode build pending.
Commit(s), or explicit uncommitted state: `749bc2a` (`handle navigation failures and offline recovery`).

Changed files and behavior:

- `BrowserController.swift` retains the active main-frame request for explicit retry, ignores canceled and stale navigation failures through its existing navigation guard, retries one offline/connection-lost GET or HEAD after connectivity returns, and stops automatic retry thereafter. It reports repeated WebContent termination distinctly and resets the counter after a committed page.
- `BrowserNavigationFailure.swift` maps App Transport Security failures, models repeated process termination, and owns the body-free GET/HEAD retry eligibility rule.
- `BrowserNavigationConnectivity.swift` uses one native `NWPathMonitor` to publish connectivity changes. It does not alter WebKit networking or the sync monitor.
- `BrowserNavigationErrorView.swift` reports connectivity recovery on offline error pages and retains its accessible refresh control.
- `checks/failures-offline/main.swift` checks production classification and automatic retry eligibility.

Acceptance cases satisfied, with evidence: source inspection confirms only current `WKNavigation` failures are applied; cancellation and download handoff remain separate; retry retains the original request; automatic retries require body-free GET/HEAD and happen at most once per failed attempt; repeated content-process failures show a stop-and-close message. The production-helper assertions passed.
Checks run, scheme/destination/workspace and results: `swiftc astra/Web/Navigation/BrowserNavigationFailure.swift checks/failures-offline/main.swift -o /tmp/astra-failures-offline-check && /tmp/astra-failures-offline-check` passed. No Xcode scheme, destination, or workspace check was run because task 29 holds the shared Xcode slot.
Checks written but not executed: none beyond the source-compiled Foundation-only assertion executable.
Pending runtime/hardware/provider cases: macOS/iOS Xcode diagnostics and build; real offline-to-online transition; DNS/reset/TLS/redirect errors; repeated WebContent termination; service-worker offline responses; GET/HEAD auto retry and POST/form/upload non-replay in WebKit.
Migration, compatibility and private-data impact: none. Failed request data remains in controller memory only. Existing diagnostics expose failure kind without URL, headers, body, or page content. Normal/private session boundaries are unchanged.
Capability gates / unresolved issues: runtime behavior of `NWPathMonitor` and platform availability remain unverified on the app deployment targets.
Merge prerequisites / follow-up ownership: task 02 is present in baseline. Primary review and Xcode verification remain pending.
