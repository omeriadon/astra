# 10-bookmarks-reading-list

Priority: P1 baseline; P2 reading list. Status: planned. Prerequisites: 03.
Branch: `astra/roadmap/10-bookmarks-reading-list`. Worktree: `../astra-worktrees/10-bookmarks-reading-list`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Bookmark currently stores ID/name/URL. Browser supports add/open/remove and portable HTML/JSON interchange; pinned tab folders are separate organization.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Models/Library/Bookmark.swift`
- `astra/UI/Content/BrowserBookmarksView.swift`
- `astra/Storage/BrowserUserData.swift`
- `astra/App/BrowserDataTransfer.swift`
- `astra/Models/Core/Browser.swift`

## Write ownership

Bookmark model/management/UI/interchange; new reading-list files only when selected; reserved workspace/persistence fields.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete rename, move, folders/groups, search, sort order and favorite selection without conflating bookmarks with pinned live tabs. Preserve stable IDs and migrate existing flat bookmarks with safe defaults.
- Import/export standard Netscape HTML and current JSON formats, rejecting executable/privileged URLs and handling escaping, invalid files and duplicate choices. Preserve existing data on a failed import and keep import/export scoped to explicit user actions.
- If reading list is selected, add URL/title/metadata and read/unread management as a distinct state on the smallest existing model boundary. Offline snapshots and sync are separate selected extensions with data-size/privacy contracts.

## Acceptance criteria

- Existing flat bookmarks migrate without loss; rename/move/order/search/favorite behavior round-trips.
- HTML/JSON round-trips names/URLs and rejects hostile links; failed imports do not replace valid data.
- Selected reading-list metadata preserves state; unselected offline/sync work creates no unused subsystem.

## Verification

Add bookmark organization/migration and hostile interchange checks; compile. Include small representative import fixtures.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Reading list is optional; offline snapshots and reading-list sync require an explicit scope decision and supported storage/export behavior.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/10-bookmarks-reading-list.md` using the dispatch template. The primary reviews; the user merges later.

## Required cache/update metadata

Preserve task29’s user-required local cache and timestamped merge contract. Every new synchronized entity, ordering/deletion scope and portable setting participates in persisted last-update metadata. Stamp actual local mutations, preserve remote/decoded timestamps, and verify that stale incoming data cannot replace newer local changes. Register added portable settings; retain explicit device-only exclusions.
