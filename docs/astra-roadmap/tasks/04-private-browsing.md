# 04-private-browsing

Priority: P0. Status: planned. Prerequisites: 03.
Branch: `astra/roadmap/04-private-browsing`. Worktree: `../astra-worktrees/04-private-browsing`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Each private window currently has an independent nonpersistent WebKit store, permissions, favicon store and download manager. Private extension/sync paths are disabled; downloaded files intentionally remain on disk.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Web/Navigation/BrowserWebSession.swift`
- `astra/Models/Core/Browser.swift`
- `astra/UI/Shell/PrivateBrowserSidebar.swift`
- `astra/UI/Shell/BrowserWindowController.swift`
- `astra/Web/Downloads/BrowserDownloadManager.swift`

## Write ownership

Private lifecycle/session paths and private shell; narrowly reserved privacy corrections in persistence, favicons, extensions or sync.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Audit all entry points: creation, duplication, popup, peek, reopen, bookmarks, remote suggestions, downloads, exported data, debug logging and OS recent items. Services resolve through the private session rather than normal singletons.
- Keep private history/address suggestions/closed tabs local and ephemeral. Private pages do not enter normal persistence, sync, favicon cache, extension contexts or another private window. Explicit bookmark/export actions must have deliberate documented behavior rather than accidental history leakage.
- Make final window cleanup idempotent for stores, permissions, pending prompts/tasks and download records. Preserve intentionally saved downloaded files. Differentiate private chrome and ensure private startup/relaunch never restores private pages.

## Acceptance criteria

- Two private windows and a normal window use distinct expected session services; no private metadata reaches normal disk snapshots/sync.
- Closing/reopening a private window loses ephemeral state and leaves explicitly downloaded files.
- Tab creation/duplication/popups/peeks preserve privacy mode; visual labels accurately reflect it.

## Verification

Add focused private-session/service-routing checks and inspect all persistence paths. Compile changed checks; storage and closing fixtures remain pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

None for the baseline scope.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/04-private-browsing.md` using the dispatch template. The primary reviews; the user merges later.
