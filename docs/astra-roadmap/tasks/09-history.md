# 09-history

Priority: P1. Status: planned. Prerequisites: 03, 04.
Branch: `astra/roadmap/09-history`. Worktree: `../astra-worktrees/09-history`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

BrowserVisit is independent of per-WebView back/forward history. Browser records visits/title changes, retention and individual/global deletion; backup deletion protection already exists.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Models/Tabs/BrowserVisit.swift`
- `astra/Models/Tabs/BrowserHistory.swift`
- `astra/Models/Core/Browser.swift`
- `astra/UI/Content/BrowserHistoryView.swift`
- `astra/Storage/BrowserPersistence.swift`

## Write ownership

Global visit recording/query/deletion and history UI; visit schema changes in reserved persistence files.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Define visit insertion for committed top-level navigations, reloads, back/forward and same-document changes. Exclude internal/private/error pages and strip embedded credentials.
- Support title/URL search, recent visits, per-URL visit count/last visit and frequent-page projections without confusing them with the WebView list. Use existing JSON/visit models unless measured scale requires a database.
- Delete individual entries and time ranges or all history; apply retention and clear derived suggestions/last-visit indexes across normal windows. Keep native live back/forward useful while preventing deleted browser-history records from returning through backups, closed tabs or import paths.

## Acceptance criteria

- Known navigation sequences produce documented visit counts and title updates; subframes/private/internal pages do not add visits.
- Time range boundaries, retention and individual/all deletion remove the intended records and derived suggestions.
- Recovering a backup cannot resurrect deleted history; clearing retains the active controller/native navigation.

## Verification

Add visit-policy/aggregation/time-range/deletion checks using synthetic dates and temporary stores; compile. Record same-document/reload fixture cases.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

None for the baseline scope.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/09-history.md` using the dispatch template. The primary reviews; the user merges later.

## Updated sync requirement

Consume task29’s timestamped history merge, deletion and clear policy. Keep visit time distinct from last modification, update freshness on actual record edits, and keep private visits excluded. History is no longer a local-only product scope; preserve device caches and sync conflict protection.
