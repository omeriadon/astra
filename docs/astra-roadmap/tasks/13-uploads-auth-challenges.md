# 13-uploads-auth-challenges

Priority: P0 / P1. Status: planned. Prerequisites: 02, 04, 05.
Branch: `astra/roadmap/13-uploads-auth-challenges`. Worktree: `../astra-worktrees/13-uploads-auth-challenges`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

WebsiteUI presents native open panels and Basic/Digest credential prompts, shared with downloads. Stale document ownership is already checked in several paths.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Web/Navigation/BrowserWebsiteUI.swift`
- `astra/Web/Navigation/BrowserController.swift`
- `astra/Web/Downloads/BrowserDownloadManager.swift`

## Write ownership

Upload/authentication presenter and delegate paths; task-owned platform upload wrappers only if needed.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete file-picker cancellation/multiple-selection, selected-file access and page-owned lifetime. Coordinate drag/drop upload and mobile photo/camera selection through supported native WebKit/platform behavior; do not rebuild HTML file inputs.
- Keep Basic/Digest challenge cancellation/retry and download/page authentication consistent. Identify host/realm and encryption state, bound repeat prompts and never persist typed passwords in browser state or logs.
- Use default native trust validation. Client certificate selection remains a public-API/keychain capability check; no allow-any-certificate override or independent validation engine. Browser-auth/AutoFill/passkey integration belongs to task 23.

## Acceptance criteria

- Navigating/closing while a chooser or auth prompt is queued completes cancellation once and cannot grant another document file/credential access.
- Single/multiple uploads preserve user choices; cancellation yields no stale URLs and scoped access is released appropriately.
- Authentication refusals/retries remain bounded; server-trust handling stays native and credentials avoid diagnostics/persistence.

## Verification

Add presenter/challenge-decision ownership checks; compile. Provide upload/realm/retry fixture cases; real file/hardware/client-certificate cases remain pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Client certificates and iOS capture/photo upload require supported APIs and platform authorization. Record unsupported combinations explicitly.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/13-uploads-auth-challenges.md` using the dispatch template. The primary reviews; the user merges later.
