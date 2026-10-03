# 21-content-blocking

Priority: P2. Status: planned. Prerequisites: 18, 20.
Branch: `astra/roadmap/21-content-blocking`. Worktree: `../astra-worktrees/21-content-blocking`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Astra ships extension packages including a blocker. A standalone browser rule-list manager must first be justified against existing extension behavior.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Web/Extensions/BrowserExtensionManager.swift`
- `astra/Extensions/SOURCES.txt`
- `astra/Web/Navigation/BrowserController.swift`
- `astra/UI/Settings/Detail/BrowserExtensionsSettingsView.swift`

## Write ownership

New minimal rule-list manager/store and feature UI only if selected; reserved WebView/session wiring and per-site exception hooks.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Record whether blocking is supplied through existing extensions, native content rule lists, or both. If extensions cover the selected need, document that path and avoid a second subsystem.
- For selected native lists, validate bounded sources, compile via WebKit, atomically replace only successful compilations and retain the last working list on update failure. Support enable/disable, refresh, version/status and per-site exceptions integrated with task 18.
- Apply lists to correct future/live session views using supported APIs. Define private-mode behavior. Show blocking state and counts only from supported observations; page breakage gets an explicit per-site exception and reset path.

## Acceptance criteria

- Invalid/download-failed lists never remove the last valid blocking configuration.
- Enable/disable/exception decisions affect the intended site/session and persist only in normal scope.
- Installed extension blockers remain functional without unintended double policy; unavailable counts are not fabricated.

## Verification

Add validation/update-failure/exception checks; compile. Keep small rule and website fixtures for later execution.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Direct rule-list management is optional. A recorded extension-only decision satisfies this packet and unblocks dependent packets without adding code.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/21-content-blocking.md` using the dispatch template. The primary reviews; the user merges later.
