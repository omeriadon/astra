# 09 History

Task / selected optional scope: Baseline history recording, query and projection, retention, time-range/per-URL/entry/all deletion, normal-window propagation, and deleted-history backup protection. No database or dependency added.

Branch / worktree / baseline commit: `astra/roadmap/09-history` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/09-history` / `b9df9763a1cd05b65dadb098dbce203e0201e2c7`.

Status: source complete; app compiler gate remains open because the Xcode MCP transport is unavailable. No retry was made.

Commit(s), or explicit uncommitted state: `e71df62` (`implement browser history visits`); handoff checkpoint follows.

Changed files and behavior:

- `BrowserController` reports successful committed page visits, including reloads, back/forward and `.other` navigations. Same-document URL changes report a visit once per URL/navigation generation; title-only changes update the associated visit. A pure policy suppresses only initial restoration replay. An explicit user navigation after a failed replay clears that suppression. WebKit's active back-forward list remains owned by each controller.
- `BrowserTab` routes visit/title callbacks from the primary controller and peeks, including after wake. Actual page-title changes now stamp the tab modification date; a title callback does not create history by itself.
- `BrowserVisit` validates HTTP(S) URLs with hosts, removes embedded credentials, supports title/URL matching, half-open time ranges, retention, title updates and per-URL count/latest-visit summaries. `Browser` exposes deterministic recent and frequent projections.
- Individual, URL, range and all-history removal create timestamped tombstones or advance the existing clear marker. Removals propagate across open normal windows, remove last-visit references and update sync persistence. Retention uses the same tombstone path. Clear removes closed-tab suggestions while preserving live controllers.
- Hydration, import and sync application filter visits against clear/tombstone clocks before any import freshness update. Legacy tab-history migration uses `.distantPast` modification time, so migration cannot defeat an existing clear marker.
- Persistence replaces the backup with the deletion state when history, closed-tab suggestions, recorded tab-history entries, tombstones or the clear marker are removed.
- The history page searches title and URL, shows visit counts, and offers entry, per-page, recent-range and all-history deletion.

Acceptance cases satisfied, with evidence:

- Synthetic model check covers URL eligibility and credential removal, deterministic IDs and past freshness for ID/timestamp-deficient legacy JSON, URL/title search, half-open date boundaries, retention, per-URL count/title/last-visit summary, title freshness, initial restoration suppression, same-document deduplication, reload commits, and user navigation after failed restoration.
- Temporary-store check writes a visit, deletes it with a tombstone, corrupts the primary snapshot, and verifies the backup does not restore it. A second case verifies the clear marker survives backup recovery when the visit array was already empty.
- Source inspection confirms private windows cannot persist history, navigation delegates report committed WebView navigation, and title-only callbacks only update an existing controller-to-visit association.

Checks run, scheme/destination/workspace and results:

- `swiftc astra/Models/Tabs/BrowserVisit.swift docs/astra-roadmap/checks-09-history.swift -o /tmp/astra-history-policy-check && /tmp/astra-history-policy-check` — passed.
- `swiftc astra/Models/Tabs/BrowserScrollPosition.swift astra/Models/Tabs/OpenPeek.swift astra/Models/Tabs/OpenTab.swift astra/Models/Tabs/BrowserVisit.swift astra/Models/Library/Bookmark.swift astra/Models/Spaces/BrowserSpace.swift astra/Models/Spaces/BrowserWorkspace.swift astra/Models/Spaces/BrowserTheme.swift astra/Models/Core/BrowserSnapshot.swift astra/Storage/BrowserPersistence.swift docs/astra-roadmap/checks-09-history-persistence.swift -o /tmp/astra-history-persistence-check && /tmp/astra-history-persistence-check` — passed against the production persistence and Codable model sources using a temporary directory.
- `swiftc -frontend -parse` on all six changed Swift production files — passed.
- `git diff --check` — passed.
- No Xcode MCP diagnostics or app build ran. The Xcode MCP transport was already recorded closed; app compile remains a required serialized primary check when the transport becomes available.

Checks written but not executed: No hosted test target or app/runtime test was run.

Pending runtime/hardware/provider cases: Real WebKit commit callback behavior for same-document transitions, redirects, scripted navigation, reload, back/forward and peeks remains unverified. App build is pending Xcode MCP. No app launch occurred.

Migration, compatibility and private-data impact: No local envelope or sync document version change. Existing `deletedVisitsAt` and `historyClearedAt` remain the merge contract from29. Legacy history with a missing ID gets a deterministic SHA-256-derived UUID from its credential-free URL, visit time and title; missing update time uses `.distantPast`. History visit times remain separate. Credentials are removed from normalized history URLs. Private history remains ephemeral and excluded from persistence/sync.

Capability gates / unresolved issues: WebKit live/native navigation entries are intentionally retained in the active controller so deleted history remains usable for current back/forward navigation. Reopened or restored historical visit records remain filtered by tombstones/clear clocks. Build and runtime evidence are pending.

Merge prerequisites / follow-up ownership: Packet13 can start from this reviewed controller callback contract: `historyVisitDidCommit(URL, title, navigationIdentifier)` for committed eligible visits; `historyVisitTitleDidChange(URL, title, navigationIdentifier)` updates only. Both closures are cleared with the controller. Upload/auth delegate behavior was not changed. Preserve packet29 tombstone, clear, cache and timestamp semantics.
