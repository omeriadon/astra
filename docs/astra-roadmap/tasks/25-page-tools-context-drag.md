# 25-page-tools-context-drag

Priority: P1. Status: planned. Prerequisites: 12, 13, 16, 17.
Branch: `astra/roadmap/25-page-tools-context-drag`. Worktree: `../astra-worktrees/25-page-tools-context-drag`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

DesktopCommands already offers file open, print, PDF/web-archive/source export. Browser context/drag behavior partly comes from WebKit and native shell code.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Web/Navigation/BrowserDesktopCommands.swift`
- `astra/App/BrowserDataTransfer.swift`
- `astra/Web/Navigation/BrowserWebView.swift`
- `astra/Web/Navigation/BrowserController.swift`
- `astra/App/AppDelegate.swift`

## Write ownership

Page export/print/share/context-menu and page/download/address drag hooks; tab-bar drag remains task 07.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete print command/sheet, PDF/archive/source save, current URL/title copying and native sharing of page/selection/image/file as supported. Destination/collision/security scope uses task 12 conventions; canceled or navigated-away exports do not write the wrong document.
- Preserve native context menus while supplying missing link open/new tab/new window/copy/download, image save/copy/open/URL, selection copy/search/look-up and page reload/save/print actions. Translation routes to selected task 26 behavior.
- Coordinate links/URLs/text into address or tab targets and files out of download UI; in-page file drop uses task 13/native behavior. Preserve supported frame/selection decisions and accessibility. Do not reimplement native editing/context APIs when already adequate.

## Acceptance criteria

- Page actions/export/share reference the current committed page and survive cancellation without orphan or wrong-page files.
- Link/image/selection actions preserve the right target/metadata, foreground policy and download permissions.
- Drag payload validation rejects privileged/malformed input and downloads drag their actual completed file.

## Verification

Add target/payload/export-generation checks where needed; compile. Record native print/save/share/context-menu/drop cases for later execution.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Complete page-plus-linked-resource saving is optional; label archive/PDF/source formats accurately and do not promise universal offline replay.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/25-page-tools-context-drag.md` using the dispatch template. The primary reviews; the user merges later.
