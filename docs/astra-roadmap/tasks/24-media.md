# 24-media

Priority: P1. Status: planned. Prerequisites: 01, 05, 16.
Branch: `astra/roadmap/24-media`. Worktree: `../astra-worktrees/24-media`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Controller observes native media playback and camera/microphone capture. Sidebar card can pause/stop capture and show available Media Session metadata; AirPlay remains native.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Web/Navigation/BrowserController.swift`
- `astra/UI/Chrome/BrowserMediaActivityView.swift`
- `astra/Web/Navigation/BrowserWebSession.swift`

## Write ownership

Media observation/controls/sidebar and protection state; PiP itself belongs exclusively to task 24a.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete media-playing indicators, available tab mute/unmute, pause/resume and metadata state through supported WebKit APIs. Distinguish playing media, audible media, muted media and capture; never infer one from another without evidence.
- Preserve native page Media Session/PiP/AirPlay behavior and connect browser activity protection for task 24a. Browser-owned global media commands exist only if public integration requires them; avoid an app-owned audio mixer/player layered over WebKit.
- Keep spatial audio acceptance explicit: website HRTF, multichannel/Atmos, supported AirPods fixed/head-tracked output are distinct checks. Do not claim stereo playback proves spatial support. Screen capture state/protection uses task 05's verified capability path.

## Acceptance criteria

- Indicators/controls target the right tab/peek and stale observations end after close/navigation.
- Pause/mute/capture changes preserve page playback semantics and do not affect another session.
- Native AirPlay/Media Session paths remain intact; unknown audible/mute/spatial state is represented honestly.

## Verification

Add media-state/ownership checks for changed logic; compile. Record later Media Session/AirPlay/audio/capture/hardware tests.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Mute/audible state and spatial output depend on exposed APIs/hardware. Explicitly required PiP is handled by the separate 24a packet, not deferred as optional.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/24-media.md` using the dispatch template. The primary reviews; the user merges later.
