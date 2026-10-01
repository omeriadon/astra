# 11-favicons

Priority: P1. Status: planned. Prerequisites: 04.
Branch: `astra/roadmap/11-favicons`. Worktree: `../astra-worktrees/11-favicons`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

FaviconStore already observes page icon metadata, fetches images, caches them and saves normal-session results; private stores are independent.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Storage/FaviconStore.swift`
- `astra/UI/Tabs/BrowserFavouriteTile.swift`
- `astra/UI/Tabs/BrowserTabRow.swift`
- `astra/Web/Navigation/BrowserController.swift`

## Write ownership

Favicon discovery/cache/fallback logic; narrowly reserved icon-only bindings in tab/start-page UI.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete origin/page association, icon choice, stale refresh and deterministic fallback icons. Bound response size, decoded dimensions, concurrent fetches and persistent cache growth; validate page ownership before accepting an asynchronous result.
- Fetch lazily and reuse current store/session configuration so private icons cannot touch disk or normal caches. Cancel work after tab/session disposal and prevent stale results from repainting another tab. Refresh invalidation responds to site-data clearing.
- Avoid a second image pipeline or snapshot system. Preserve website identity when an icon URL changes origin, and treat page metadata/remote image bytes as untrusted.

## Acceptance criteria

- Missing/invalid icons show a consistent fallback; stale icons refresh within the defined cache policy.
- A delayed response cannot replace another tab's icon; cache/network limits are enforced.
- Private results remain ephemeral and clearing data invalidates the relevant owned icon entries.

## Verification

Add icon key/selection/invalidation and size-limit checks with synthetic metadata; compile. Record real-page/icon decode cases.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

None for the baseline scope.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/11-favicons.md` using the dispatch template. The primary reviews; the user merges later.
