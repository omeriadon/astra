# 16-chrome-find-zoom

Priority: P1. Status: planned. Prerequisites: 01, 05, 07.
Branch: `astra/roadmap/16-chrome-find-zoom`. Worktree: `../astra-worktrees/16-chrome-find-zoom`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Navigation controls already show back/forward menus, reload/stop and connection information. BrowserFindBar and controller find/zoom state exist.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/UI/Chrome/BrowserNavigationControls.swift`
- `astra/UI/Chrome/BrowserFindBar.swift`
- `astra/UI/Chrome/BrowserLoadingBar.swift`
- `astra/UI/AddressBar/BrowserAddressField.swift`
- `astra/Web/Navigation/BrowserController.swift`
- `astra/UI/Content/BrowserPageView.swift`

## Write ownership

Chrome state/bindings, find and page zoom controller/UI paths; feature-owned zoom preference keys.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Ensure selected tab's active controller drives URL/title/loading/progress/back/forward/reload-stop/security/audio/permission state, including peeks. Editing an address must not be overwritten by unrelated loading updates.
- Complete find text, next/previous, close, no-match and supported match-count presentation. Native WebKit performs searching; avoid DOM walking or counting a different document. Task 17 wires Cmd-F/G/Shift-G.
- Complete bounded zoom in/out/reset, visible indicator, per-tab state and default preference. Supply per-site persistence hooks to task 18. Tabs with pending/native restoration must apply zoom without recreating views. Reader and PiP state join the same existing ownership boundary when implemented.

## Acceptance criteria

- Switching tabs/peeks changes all chrome consistently; late callbacks and address editing cannot display another document's state.
- Find generations discard stale results; next/previous/close and no-match work with the native mechanism.
- Zoom respects bounds/defaults and restores after tab wake without clobbering per-site rules.

## Verification

Add find-generation/zoom/state-routing checks where logic changes; compile. Source-inspect UI/accessibility and record later focus/selection cases.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

A match count is shown only when supported/measured by the actual find API; unknown counts remain unknown.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/16-chrome-find-zoom.md` using the dispatch template. The primary reviews; the user merges later.
