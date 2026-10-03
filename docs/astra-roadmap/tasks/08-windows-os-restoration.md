# 08-windows-os-restoration

Priority: P1. Status: planned. Prerequisites: 07.
Branch: `astra/roadmap/08-windows-os-restoration`. Worktree: `../astra-worktrees/08-windows-os-restoration`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

AppDelegate creates AppKit browser/private/Mini Astra windows. Window registry coordinates shared normal state; windows currently start centered with a computed frame.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/App/AppDelegate.swift`
- `astra/UI/Shell/BrowserWindowController.swift`
- `astra/UI/Shell/MiniAstraWindowController.swift`
- `astra/Models/Core/BrowserWindowRegistry.swift`
- `astra/Storage/BrowserPersistence.swift`

## Write ownership

Window management/records, registry ownership and OS-event paths; persisted window schema reservation.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete new/close/reopen/restore windows and tab selection association while preserving shared normal-window organization. Private windows never enter durable restore records; Mini Astra follows its explicit lifecycle.
- Save geometry and safely restore against visible display bounds after monitor removal, resolution changes and scale changes. Coordinate browser fullscreen with website fullscreen and later PiP without hiding essential exit/security controls.
- Handle terminate/logout/reboot restoration, canceled close/quit, sleep/wake and activation. Save relevant window selection/frame changes without high-frequency synchronous I/O. Popup tab/window choice consumes task 02 policy rather than a second policy.

## Acceptance criteria

- Restored normal windows reference valid tabs and visible frames; private windows are absent.
- Removing a display cannot strand a restored window; close/quit cancellation leaves the live model intact.
- Fullscreen and focus changes target the correct window and do not recreate pages or interrupt PiP/capture.

## Verification

Add geometry-clamping/window-record/selection checks; compile. Record monitor, fullscreen, sleep/wake and logout cases for later execution.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

None for the baseline scope.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/08-windows-os-restoration.md` using the dispatch template. The primary reviews; the user merges later.
