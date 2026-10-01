# 06-failures-offline

Priority: P0. Status: planned. Prerequisites: 02.
Branch: `astra/roadmap/06-failures-offline`. Worktree: `../astra-worktrees/06-failures-offline`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Navigation errors are modeled and shown by native error views. WebContent termination keeps the tab and records a failure; canceled/download transitions have special handling.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Web/Navigation/BrowserNavigationFailure.swift`
- `astra/Web/Navigation/BrowserController.swift`
- `astra/UI/Content/BrowserNavigationErrorView.swift`
- `astra/UI/Settings/Detail/BrowserFailedWebsiteStatesSettingsView.swift`

## Write ownership

Failure mapping/controller recovery and error views; minimal connectivity observation if absent.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Cover DNS, offline, reset, TLS, unsupported URL, redirect-loop and WebContent termination states with retry and redacted diagnostic copy. Ignore obsolete/canceled failures and preserve the correct tab/request.
- Define bounded repeat-crash behavior: no endless reload loops and no app-wide crash. Connectivity observation updates browser chrome without replacing WebKit network behavior. Retry automatically only a explicitly eligible idempotent failed load; POST/form/upload requests require deliberate user retry and confirmation where applicable.
- Downloads consume network-return policy through their own manager. Service-worker/offline cache behavior remains engine-owned; error chrome must not interfere with a website that has a working offline response.

## Acceptance criteria

- Old requests cannot replace the current page's error; failed/canceled/download transitions map distinctly.
- Repeated content crashes preserve the tab and stop automatic retry; retry targets the correct URL/request.
- Offline-to-online handling never silently resubmits POST or loops on a permanent error.

## Verification

Add error classification and bounded retry policy checks; compile. Record process termination/network transition fixture cases; use synthetic diagnostic data.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

None for the baseline scope.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/06-failures-offline.md` using the dispatch template. The primary reviews; the user merges later.
