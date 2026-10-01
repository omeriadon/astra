# 01-lifecycle

Priority: P0. Status: planned. Prerequisites: 00.
Branch: `astra/roadmap/01-lifecycle`. Worktree: `../astra-worktrees/01-lifecycle`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

BrowserTab stores live or reconstructible page state; BrowserController lazily owns a WebView and delegate callbacks. Existing safeguards use loading, dirty input, media and camera/microphone state. Automatic destructive hibernation was removed.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Models/Tabs/BrowserTab.swift`
- `astra/Models/Tabs/BrowserPeek.swift`
- `astra/Web/Navigation/BrowserController.swift`
- `astra/Web/Navigation/BrowserWebView.swift`
- `astra/App/AppDelegate.swift`

## Write ownership

The listed tab/controller/WebView files; lifecycle-only hooks in Browser.swift and AppDelegate.swift; unique lifecycle checks.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Trace create, attach, detach, switch, peek promotion, hibernate, wake and close. Keep controller/WebView identity stable through SwiftUI updates and make cleanup of observers, message handlers, tasks and delegates explicit.
- Reject stale callbacks using view/document ownership. Close invalidates pending prompts, snapshots, favicon/media work and navigation updates. Define manual hibernation state/fallback and keep active capture, playback, unsaved work and required PiP protected.
- Under memory pressure release owned previews/caches first and retain WebKit's idle policy. Do not add automatic destructive hibernation or a live-WebView cap until reliable capture/draft/PiP protection exists. Use the smallest lifecycle correction; split a delegate only if needed for that correction.

## Acceptance criteria

- A->B tab switching does not rebuild A, and a callback from a closed/replaced document cannot update B.
- Wake restores the correct URL/zoom/scroll/history where supported, preserves session identity and has a clear fallback.
- Cleanup is idempotent and memory-pressure handling cannot silently destroy screen sharing, drafts or PiP.

## Verification

Add focused identity/invalidation/reconstruction checks to a new test file; compile with Xcode MCP. Record manual capture/PiP/switch/pressure cases for later execution.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Automatic destruction remains disabled until public state/protection mechanisms cover screen-only capture and PiP. A camera/microphone heuristic is insufficient.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/01-lifecycle.md` using the dispatch template. The primary reviews; the user merges later.
