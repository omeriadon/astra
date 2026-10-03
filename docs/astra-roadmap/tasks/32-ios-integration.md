# 32-ios-integration

Priority: P1 cross-platform follow-up. Status: planned. Prerequisites: 17, 23, 24, 24a, 25, 28, 31.
Branch: `astra/roadmap/32-ios-integration`. Worktree: `../astra-worktrees/32-ios-integration`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

The shared app target includes iOS, with a SwiftUI WindowGroup entry point and compact shells. Desktop-specific prompt/services need separate platform behavior.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/App/browserApp.swift`
- `astra/UI/Content/ContentView.swift`
- `astra/UI/Shell/CompactBrowserShell.swift`
- `astra/UI/Shell/CompactBrowserNavigation.swift`
- `astra/Web/Navigation/BrowserWebsiteUI.swift`
- `astra/Web/Navigation/BrowserWebView.swift`
- `astra/Special/Info.plist`

## Write ownership

iOS/iPad scene/chrome/platform adapters and required target capabilities; shared files only for necessary platform-safe corrections.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Bring selected baseline features to iOS/iPad: incoming URLs, scenes/multiple windows, tab/state restore, private lifecycle, native permissions/uploads/share/print, iPad keyboard/drag and memory pressure. Keep browser model contracts common while platform presentation stays native.
- Configure default-browser eligibility/entitlements only from supported Apple requirements. Downloads obey foreground/background platform limits and private cleanup. Share extensions are optional separately scoped targets.
- PiP is required: implement supported WebKit configuration/native entry, originating-scene restoration and safe tab lifecycle using task 24a's contract. Verify audio/background requirements instead of claiming continued playback from configuration alone. Keep focus/scene selection and capture permissions correct across suspend/resume.

## Acceptance criteria

- Shared source compiles for the declared iOS destination and macOS remains intact.
- Incoming URL, scene restoration, private cleanup, file/permission/share flows and keyboard/drop policies have explicit iOS behavior.
- Required PiP has supported configuration/control/restoration paths and documented pending device/background checks; unavailable entitlements are recorded.

## Verification

Use Xcode MCP for relevant iOS destination diagnostics/build and unique scene/routing checks. No simulator/device/app launch; hardware/scene/PiP behavior remains pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Default-browser configuration and background/PiP behavior require capability/device evidence; share extension is optional. This packet does not add unrelated watchOS/visionOS scope.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/32-ios-integration.md` using the dispatch template. The primary reviews; the user merges later.
