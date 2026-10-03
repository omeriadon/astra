# 30-profiles

Priority: P2. Status: planned. Prerequisites: 04, 18, 22, 28, 29.
Branch: `astra/roadmap/30-profiles`. Worktree: `../astra-worktrees/30-profiles`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Spaces currently organize tabs and share normal website data. They are not profiles; introducing profiles changes service/storage ownership.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Web/Navigation/BrowserWebSession.swift`
- `astra/Models/Core/BrowserWindowRegistry.swift`
- `astra/Storage/BrowserPersistence.swift`
- `astra/Web/Extensions/BrowserExtensionManager.swift`
- `astra/Storage/BrowserSync.swift`

## Write ownership

Profile model/storage/session selection and feature UI; shared-service refactors only if selected and necessary.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Dispatch implementation only if profiles are selected. Define separate history, bookmarks, website data, extensions, settings, downloads policy and profile appearance while spaces remain organization inside a profile.
- Migrate existing normal data into one default profile without changing IDs or losing cookies. Verify public support for identified persistent WebKit data stores. Refactor singleton routing only where required so tabs/windows bind to the correct profile session.
- Define private windows relative to profiles, switching without data mixing, deletion/export/reset and sync account/profile identity. Deleting a profile does not accidentally delete another profile's files. Keep the first implementation bounded; no generic multi-tenant service framework.

## Acceptance criteria

- Existing users migrate into the default profile unchanged; two profiles remain isolated across services and restarts.
- Switch/close/private-window operations cannot reuse the wrong data store or extension context.
- Deletion and sync scope are explicit and recoverable; unsupported multi-store APIs block implementation rather than simulate isolation.

## Verification

Add profile-routing/migration/isolation checks when selected; compile. Real cookie/storage/extension isolation remains pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Optional feature with a product decision and supported persistent-store gate. A decision to keep spaces without profiles closes this packet without code.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/30-profiles.md` using the dispatch template. The primary reviews; the user merges later.

## Required cache/update metadata

Preserve task29’s user-required local cache and timestamped merge contract. Every new synchronized entity, ordering/deletion scope and portable setting participates in persisted last-update metadata. Stamp actual local mutations, preserve remote/decoded timestamps, and verify that stale incoming data cannot replace newer local changes. Register added portable settings; retain explicit device-only exclusions.
