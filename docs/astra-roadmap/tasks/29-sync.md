# 29-sync

Priority: P1 existing contract; P2 expansion. Status: planned. Prerequisites: 03, 04, 07, 09, 10, 28.
Branch: `astra/roadmap/29-sync`. Worktree: `../astra-worktrees/29-sync`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

BrowserSync and BrowserSyncDocument already support account sync, settings, tab/workspace/bookmark merge, tombstones, bounds/retry and network-return behavior. History/native restoration/local files are excluded.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Storage/BrowserSync.swift`
- `astra/Models/Core/BrowserSyncDocument.swift`
- `astra/Models/Core/Browser.swift`
- `astra/Storage/BrowserSessionStore.swift`
- `astra/UI/Settings/Detail/BrowserAccountSettingsView.swift`

## Write ownership

Client sync/merge/account behavior and payload schema; server changes are outside this worktree/task.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Preserve/harden the existing client/server contract for bookmarks, open tabs, spaces and selected settings. Confirm stable IDs, modified dates, conflict rules, tombstones/deletion propagation, bounded retries and offline reconciliation without resurrecting deleted data or replacing active local pages.
- Keep private data, local files/bookmarks, interaction blobs and credentials out of payloads. Account sign-out/expired token state has deliberate local-data semantics; network failure is not interpreted as deletion.
- History/reading-list sync and end-to-end encryption are explicit extensions. Document server schema/key lifecycle/migration requirements before adding them; sensitive-data encryption must use established cryptography and a separately reviewed recovery design. This browser plan does not authorize server implementation or deployment.

## Acceptance criteria

- Two synthetic device states converge deterministically for changes/deletes and preserve active local controllers.
- Invalid/oversized/future payloads and expired sessions leave recoverable local data and actionable account state.
- Private/sensitive/local-only fields never appear in outgoing documents; expansion gates identify required server work.

## Verification

Add conflict/tombstone/schema/payload/retry checks without a live server; compile. Real multi-device and account/provider behavior remains pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

History sync, reading-list sync and E2EE require selected scope, server agreement and reviewed security/key recovery. Existing behavior stays compatible until then.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/29-sync.md` using the dispatch template. The primary reviews; the user merges later.
