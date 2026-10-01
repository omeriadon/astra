# 07-tabs-spaces

Priority: P1. Status: planned. Prerequisites: 03, 04.
Branch: `astra/roadmap/07-tabs-spaces`. Worktree: `../astra-worktrees/07-tabs-spaces`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Browser already supports creation, duplication, close/reopen, bulk closing, MRU switching, ordering, pins/folders and spaces. Peeks and favorite tabs are existing Astra concepts.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Models/Core/Browser.swift`
- `astra/Models/Spaces/BrowserWorkspace.swift`
- `astra/Models/Spaces/BrowserSpace.swift`
- `astra/UI/Tabs/BrowserTabRow.swift`
- `astra/UI/Tabs/BrowserTabDragCoordinator.swift`
- `astra/UI/Tabs/ControlTabSwitcher.swift`

## Write ownership

Tab organization operations/models and tab UI/drag/switcher; relevant OpenTab schema extension reserved with persistence owner.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete creation from blank/link/URL/duplicate, close/others/before/after/reopen and selected-tab fallback. Keep pinned/favorite closure and ordering rules explicit; preserve peeks and per-tab URL/title/favicon/loading/zoom/settings.
- Define new-tab placement, stable ordering and persisted last-used metadata if required by MRU behavior. Drag within spaces/folders and transfer across normal windows without stale controllers or duplicate records. Preserve current shared normal-window semantics; a transfer may change organization rather than invent independent window tab sets.
- Private-to-normal movement must not silently transfer a session/WebView; use an explicit new navigation if such movement is selected. Group/space naming, membership, selection and deletion round-trip through persistence.

## Acceptance criteria

- All close variants leave a valid selection, respect pins and retain correct reopened state/order.
- Reorder/duplicate/group deletion produce no duplicate/missing IDs; order and selection survive restoration.
- MRU/next/previous and drag operations preserve controller/session ownership, including peeks.

## Verification

Add model-level tab/order/selection/bulk-close checks; compile. Document keyboard/drag/focus cases for later app testing.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

None for the baseline scope.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/07-tabs-spaces.md` using the dispatch template. The primary reviews; the user merges later.

## Required cache/update metadata

Preserve task29’s user-required local cache and timestamped merge contract. Every new synchronized entity, ordering/deletion scope and portable setting participates in persisted last-update metadata. Stamp actual local mutations, preserve remote/decoded timestamps, and verify that stale incoming data cannot replace newer local changes. Register added portable settings; retain explicit device-only exclusions.
