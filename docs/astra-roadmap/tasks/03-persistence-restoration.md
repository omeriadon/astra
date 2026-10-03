# 03-persistence-restoration

Priority: P0. Status: planned. Prerequisites: 01.
Branch: `astra/roadmap/03-persistence-restoration`. Worktree: `../astra-worktrees/03-persistence-restoration`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Persistence already uses a versioned atomic snapshot and backup. OpenTab supports encrypted local restoration data; URL fallback exists. BrowserSessionStore is the sync-token Keychain store, not a tab-session database.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Storage/BrowserPersistence.swift`
- `astra/Storage/BrowserRestorationStore.swift`
- `astra/Models/Tabs/OpenTab.swift`
- `astra/Models/Tabs/OpenPeek.swift`
- `astra/Models/Core/BrowserSnapshot.swift`
- `astra/Models/Core/Browser.swift`

## Write ownership

Persisted DTOs and stores above; hydrate/save/startup hooks in Browser.swift and AppDelegate.swift; task-owned migration fixtures.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete coherent persistence of tab order, selection, spaces, pins, closed tabs and practical local page state. Define a versioned window-record extension for task 08 without changing shared-tab behavior. Preserve serialized background writes and visible save failures on close/quit.
- Define clean/unclean shutdown metadata and startup choices: restore, blank tab or configured homepage. Recovery loads the latest valid compatible generation, retains corrupt/future data and avoids overwriting unsupported formats. Defaults and legacy formats migrate deterministically.
- Document which native back/forward, scroll and interaction state survive hibernation versus relaunch. Never promise drafts/sessionStorage restoration beyond proven WebKit support. Keep sensitive restoration encrypted locally, exclude private state and sync, and handle unavailable Keychain/restoration data safely.

## Acceptance criteria

- Interruption, corrupt primary, corrupt backup, missing key and future schema cases preserve data and yield a coherent fallback/error.
- Selection/order/pins/spaces survive round-trip; migrations preserve IDs and can be repeated without duplication.
- History deletion cannot return from retained snapshots, and close/quit waits for the relevant durable write.

## Verification

Extend existing recovery coverage in a unique test file using temporary directories and old/future DTO fixtures; compile via Xcode MCP. Relaunch/crash behavior remains pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

None for the baseline scope.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/03-persistence-restoration.md` using the dispatch template. The primary reviews; the user merges later.
