# 31-macos-automation-webapps

Priority: P1 integration; P2 additions. Status: planned. Prerequisites: 08, 17, 23, 27, 28.
Branch: `astra/roadmap/31-macos-automation-webapps`. Worktree: `../astra-worktrees/31-macos-automation-webapps`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

macOS already has AppKit shell/window ownership, URL registration, default-browser UI, Mini Astra and browser authentication-session capabilities.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/App/AppDelegate.swift`
- `astra/App/MiniAstraShortcut.swift`
- `astra/Special/Info.plist`
- `astra/UI/Settings/Detail/BrowserGeneralSettingsView.swift`
- `astra/UI/Shell/BrowserWindowController.swift`

## Write ownership

macOS URL/default-browser/Dock/Services integration and selected automation/web-app feature files; reserved project/entitlement changes.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete default-browser/LaunchServices registration, external URL opening before/after startup, Dock commands, native sharing/Services and current window/menu correctness. Preserve Mini Astra behavior and authentication launch routing.
- If automation is selected, define supported open/create/close/list/command actions through App Intents/Shortcuts or AppleScript; validate caller parameters and restrict private/privileged access. Do not expose arbitrary webpage JavaScript execution by default.
- If PWA-like installed sites are selected, validate manifest metadata/icon/launch URLs, store explicit installations, define standalone window/session behavior and uninstall. Handoff/Spotlight/recent pages are optional with privacy filtering. Supported engine web app features are not automatically third-party browser installation capabilities.

## Acceptance criteria

- Cold/warm external URL launches and default-browser status use the proper current session/window.
- Dock/Services/menu actions work from valid state and omit private data.
- Selected automation/installed-site integrations validate origins/metadata, preserve privacy and use honest supported platform behavior.

## Verification

Add URL launch/manifest/caller-filter checks for changed logic; compile. LaunchServices/Dock/Services/Shortcuts/standalone window behavior remains pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Automation, PWA-like installs, Handoff and Spotlight require selected scope and API/configuration gates; no legacy Touch Bar work unless explicitly selected.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/31-macos-automation-webapps.md` using the dispatch template. The primary reviews; the user merges later.
