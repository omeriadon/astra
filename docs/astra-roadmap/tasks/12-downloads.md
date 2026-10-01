# 12-downloads

Priority: P1. Status: planned. Prerequisites: 02, 04, 05.
Branch: `astra/roadmap/12-downloads`. Worktree: `../astra-worktrees/12-downloads`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

BrowserDownloadManager already tracks native and segmented downloads, persisted records, resume data, quarantine and file actions. Existing filename renaming can run asynchronously.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Web/Downloads/BrowserDownloadManager.swift`
- `astra/Web/Downloads/SegmentedDownloadEngine.swift`
- `astra/Models/Library/BrowserDownload.swift`
- `astra/UI/Chrome/DownloadsSidebarView.swift`
- `astra/Web/Downloads/BrowserDownloadedFile.swift`

## Write ownership

Download manager/models/sidebar and destination settings component; task-owned defaults keys and fixtures.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete destination preference/Ask Where to Save, native selection, sandbox access, safe filenames, collision handling and cleanup of partial files. Respect WebKit suggested names; sanitize filesystem-invalid components and revalidate async renames.
- Expose active/completed/failed state, bytes/total, cancel/retry and supported resume. Speed/ETA are optional display projections, not a new transfer engine. Maintain open/reveal/remove-record distinctions and persistent normal history.
- Enforce multiple automatic-download policy via task 05; preserve authentication, redirect confirmation, quarantine and private-session cleanup for native/resumed/segmented paths. Network loss and quit must not corrupt completed files or retain invalid resume claims. Keep segmentation only where validators/ranges make it safe.

## Acceptance criteria

- Collision/path traversal/invalid names cannot overwrite or escape the selected destination.
- Cancel/retry/resume/network-loss cases have consistent state and cleanup; completed files retain quarantine after rename.
- Private records disappear on cleanup while explicit files remain; changing/removing a record during async work cannot affect another item.

## Verification

Add filename/destination/state/validator checks and small download fixtures; compile. Quarantine, sandbox save panels and resume execution remain pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Resume depends on WebKit/server support; dangerous-file warnings and speed/ETA are optional. Do not launch downloaded files during verification.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/12-downloads.md` using the dispatch template. The primary reviews; the user merges later.
