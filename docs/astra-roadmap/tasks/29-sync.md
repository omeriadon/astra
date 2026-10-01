# 29-sync

Priority: P1 existing contract; P2 expansion. Status: planned. Prerequisites: reviewed 00/01 baseline; user priority override. Later packets consume this upgraded contract.
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

## User priority override: local cache and last-updated conflict protection

The user reported `Enter a valid HTTPS sync server URL` and missing unsynced settings. Implement these requirements now, before the remaining queue:

- Normalize and validate the sync endpoint at one shared boundary. Keep production HTTPS validation and native TLS trust intact. Cover whitespace, scheme case, omitted scheme, IPv4/IPv6/port, malformed URLs and legacy/default endpoint configuration. Invalid configuration is repairable without erasing cached data. Do not call a transport or TLS failure an invalid URL. Bind credentials to their endpoint when endpoint changes could otherwise send a token to another server.
- Treat local device state as the working source of truth. Load cached settings and browser records before initial sync; failed/offline sync, expired sign-in and sign-out retain normal local data. Fix the hydrate/sync placeholder race so cache loading cannot be skipped and overwritten by empty or stale remote state. Persist downloaded/merged state locally before reporting success. Protect local edits made while network/merge work awaits.
- Every synchronized entity/collection/setting has a persisted last-update timestamp. Reuse existing `modifiedAt` and `favouritesModifiedAt` where they already express that meaning; add missing fields with deterministic legacy decoding defaults. Cover tabs, bookmarks, visit history, spaces, pinned folders, workspace organization/selection, individual portable settings and deletion/clear metadata. Changes update timestamps at the actual mutation; serialization, restoration and receipt of remote data do not fabricate newer edits.
- Merge newer content at the entity level. Timestamped deletion/tombstones and history-clear policy prevent resurrection. Preserve stable IDs and deterministic tie behavior. A stale remote record must not replace a newer local record, including edits made during a sync request. Avoid whole-dictionary or whole-workspace overwrite that discards a newer nested edit.
- Include history in the user-selected sync scope with private/local-file/credential exclusions and precise clear/delete propagation. Update account disclosure to match actual payload behavior. Keep device-only settings, tokens, endpoints and filesystem access data outside portable sync. Expand the portable settings registry to the actual supported settings rather than seven historical keys, and establish a clear registration rule for future feature keys.
- Backward-compatible migration preserves existing snapshots/settings and v1/v2 sync documents. Document payload evolution and reject unknown future formats without resetting the cache. The current server stores opaque snapshots; inspect the client/server contract rather than assume endpoints must change. No server edits or deployment occur here.

Acceptance: reproducible Foundation-only URL and model-merge/cache regression checks cover stale/new/tied data, legacy decoding, deletes/clear, offline/relaunch and changes during fetch. Checks exercise real production helpers/models, not source-text assertions or copied merge implementations. Compile affected app code through Xcode MCP. No app launch or hosted-test execution. Preserve the original checkout and every other packet's protected behavior.
