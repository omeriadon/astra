# 15-address-intelligence

Priority: P1. Status: planned. Prerequisites: 09, 10, 14.
Branch: `astra/roadmap/15-address-intelligence`. Worktree: `../astra-worktrees/15-address-intelligence`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

New-tab search already ranks action/history results and Google suggestions. The address field and new-tab field currently have separate presentation/state paths.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Models/Search/BrowserSearch.swift`
- `astra/Models/Search/BrowserSearchMatching.swift`
- `astra/Models/Search/BrowserSearchResult.swift`
- `astra/UI/AddressBar/BrowserAddressField.swift`
- `astra/UI/Content/NewTabView.swift`

## Write ownership

Search result projection/ranking/state and address autocomplete presentation; read-only integration with history/bookmarks/open tabs.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Reuse existing result models for history, bookmarks, open-tab matching, URL completion/domain prioritization and configured remote suggestions. Define a deterministic frequency/recency ranking and deduplicate by meaningful destination/result type.
- Support keyboard selection, submit/escape, inline completion and deleting an eligible history suggestion. Open-tab matches switch to the right existing tab/session rather than blindly loading a URL. Synchronize query generations/provider changes without stale results or focus jumps.
- Keep private suggestions constrained to private/currently allowed sources. Clipboard URL detection and website search-engine discovery are optional; each needs explicit user initiation/privacy behavior and untrusted template validation.

## Acceptance criteria

- Fixed source fixtures produce stable ranking/deduplication; changing a query cannot accept old network results.
- Keyboard/inline selection submits the displayed target; deleting history removes derived results without deleting bookmarks.
- Open-tab matches preserve privacy/window ownership and never expose private tab titles/URLs to normal autocomplete.

## Verification

Add ranking/selection/generation/privacy checks in a unique test file; compile. Record keyboard/focus/completion visual cases.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Clipboard inspection and automatic website-engine discovery require explicit selection; do not add background clipboard reads by default.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/15-address-intelligence.md` using the dispatch template. The primary reviews; the user merges later.
