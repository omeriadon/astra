# 19-start-page

Priority: P1. Status: build verified. Prerequisites: 07, 09, 10, 11, 15.
Branch: `astra/roadmap/19-start-page`. Worktree: `../astra-worktrees/19-start-page`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

NewTabView already offers browser search/actions and Astra has space themes/favorite tiles. Reuse those models and visual patterns.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/UI/Content/NewTabView.swift`
- `astra/UI/Tabs/BrowserFavouriteTile.swift`
- `astra/UI/Background/BrowserThemeBackground.swift`
- `astra/Models/Search/BrowserSearch.swift`

## Write ownership

Start-page presentation/preferences and favorite/recent/frequent projections; theme editor changes only when required.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Compose ordered favorites, recent/frequent visits, recently closed tabs and the existing search field. Opening/reopening uses established browser operations and preserves background/private behavior.
- Support existing theme/background choices and explicit module visibility preferences without a general widget framework. Empty states must work on first launch or cleared data. Private start pages show no normal browsing history and avoid remote previews by default.
- A privacy report appears only if supported data exists; custom widgets are optional. Compute history/frequency projections outside view hot paths where needed and load favicons lazily.

## Acceptance criteria

- First launch, empty/cleared data, restored favorites and normal/private start pages have correct content.
- Ordering/module settings persist and search/reopen/open actions target the current browser/session.
- Existing space themes/layout remain consistent; no fabricated blocked counts or privacy reports appear.

## Verification

Source-inspect view identity/privacy/data projections and use focused checks for changed ordering; smallest Xcode diagnostics as needed. Visual execution remains pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Custom widgets, remote previews and privacy report modules require selected scope and real data sources.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/19-start-page.md` using the dispatch template. The primary reviews; the user merges later.
