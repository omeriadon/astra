# 22-extensions

Priority: P1 existing support; P2 expansion. Status: planned. Prerequisites: 02, 05, 07, 08, 21.
Branch: `astra/roadmap/22-extensions`. Worktree: `../astra-worktrees/22-extensions`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

BrowserExtensionManager already uses Web Extension APIs, package installation, window/tab hosting, popup UI, permission summaries and private-path blocking.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Web/Extensions/BrowserExtensionManager.swift`
- `astra/Web/Extensions/BrowserExtensionWindow.swift`
- `astra/Web/Extensions/BrowserExtensionPopupWindow.swift`
- `astra/Web/Extensions/ChromeExtensionPackage.swift`
- `astra/UI/Settings/Detail/BrowserExtensionsSettingsView.swift`
- `astra/UI/Settings/Detail/BrowserExtensionDetailView.swift`

## Write ownership

Extension manager/package/window/popup models and settings UI; narrowly reserved browser/tab lifecycle callbacks.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete install/remove/enable/disable, toolbar/menu actions, settings and per-site access using public Apple hosting. Validate archive paths, extraction size/count, manifests and update identities; destructive removal handles owned storage deliberately.
- Keep extension tab/window IDs, focus and background lifecycle consistent with Browser ownership. Document the supported content script, messaging, storage and permissions surface; do not implement a new Chrome compatibility layer. Unavailable native messaging or other APIs remain explicitly unsupported.
- Define updates, permission escalation/reapproval and last-working rollback behavior before adding automatic update sources. Preserve private exclusion unless separately selected with an explicit isolated design. Coordinate blocking exceptions with task 21.

## Acceptance criteria

- Enable/remove/update transitions cannot leave stale toolbar items, contexts or tab/window IDs.
- Hostile archives and unapproved expanded permissions are rejected without harming existing extensions.
- Supported script/messaging/storage behavior has a compatibility matrix, and private pages cannot be enumerated or operated through normal extension contexts.

## Verification

Add bounded archive/permission-change/ID-lifetime checks; compile. Installed extension/browser compatibility remains pending execution.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Extension catalogs/automatic updates and private extension hosting require selected scope. Unsupported public APIs are not emulated.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/22-extensions.md` using the dispatch template. The primary reviews; the user merges later.
