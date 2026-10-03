# 17-keyboard-menus

Priority: P1. Status: planned. Prerequisites: 08, 16.
Branch: `astra/roadmap/17-keyboard-menus`. Worktree: `../astra-worktrees/17-keyboard-menus`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

AppDelegate already owns application menus and most navigation, tab, find, zoom, export and developer actions. Tab switcher handling and page responder shortcuts coexist.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/App/AppDelegate.swift`
- `astra/UI/Tabs/ControlTabSwitcher.swift`
- `astra/Web/Navigation/BrowserController.swift`
- `astra/Models/Core/BrowserWindowRegistry.swift`

## Write ownership

App menus, responder validation, keyboard handlers and developer preference/commands; preserve unrelated window actions.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Audit new/close/reopen/next/previous tab, new/private window, focus address, reload/force reload, back/forward, find, downloads/history/bookmarks, zoom and fullscreen shortcuts. Add required PiP command hooks after task 24a through a serialized follow-up.
- Keep File/Edit/View/History/Bookmarks/Window/Developer commands synchronized with focused window/tab availability. Preserve native text editing, webpage input and OS responder behavior; browser interception must not swallow ordinary page shortcuts or IME input.
- Expose inspect-page/inspect-element only through supported Web Inspector hosting, with developer-mode preference and availability gating. Dynamic history/bookmark/window menu entries use current IDs/state and correct private behavior.

## Acceptance criteria

- Each browser shortcut has one owner and correct enabled state for blank/internal/loading/hibernated/failed pages.
- Actions operate on the focused window/active peek rather than another registry entry; text editing/page input retains expected shortcuts.
- Developer controls reflect actual inspector availability, and menus do not retain closed/private tabs.

## Verification

Add command validation/target-resolution checks where possible; compile. Source-inspect shortcut conflicts; keyboard/runtime inspector cases remain pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

None for the baseline scope.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/17-keyboard-menus.md` using the dispatch template. The primary reviews; the user merges later.
