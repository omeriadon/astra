# 27-internal-urls

Priority: P1 native pages; P2 scheme. Status: planned. Prerequisites: 02, 03, 17, 20.
Branch: `astra/roadmap/27-internal-urls`. Worktree: `../astra-worktrees/27-internal-urls`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

BrowserInternalPage already represents settings, history, bookmarks, theme editor and debug failure pages as native pages with persistence IDs.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Models/Tabs/BrowserTab.swift`
- `astra/Models/Core/Browser.swift`
- `astra/UI/Content/BrowserPageView.swift`
- `astra/Models/Search/BrowserSearchAction.swift`
- `astra/Web/Navigation/BrowserController.swift`

## Write ownership

Internal page routing/persistence IDs and UI command mapping; optional custom URL parser/registration with primary-reserved plist changes.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Keep existing native pages first class and route new-tab/settings/history/downloads/extensions/version/debug destinations to their actual native views. Reuse enum/state routing rather than a privileged HTML website.
- If astra:// namespace is selected, validate allowed hosts/path/query with URLComponents and an explicit allowlist. Separate external URL-opening intent from website navigation; a page link or script message cannot invoke privileged internal actions or arbitrary file/system operations.
- Define navigation/back behavior, display identity and versioned persistence for internal pages. Imported bookmarks, sync documents and extension navigation may not mint internal privileges. Error/diagnostic pages bind to the current controller and use redacted data.

## Acceptance criteria

- All existing page IDs restore and map to the correct view; unknown destinations fail safely.
- Synthetic website/extension/imported astra:// links cannot run clear-data/settings mutation or privileged commands.
- Internal identities cannot be spoofed by ordinary web content, and debug-only pages are excluded from release routing.

## Verification

Add allowlist/encoding/source-trust/persistence routing checks; compile. Source-inspect all navigation/OS-opening entry points.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Custom scheme registration is optional. Existing native pages remain complete without adding a web scheme or privileged script bridge.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/27-internal-urls.md` using the dispatch template. The primary reviews; the user merges later.
