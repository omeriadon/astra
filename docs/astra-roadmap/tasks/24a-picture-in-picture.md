# 24a-picture-in-picture

Priority: P1 required. Status: planned. Prerequisites: 17, 24.
Branch: `astra/roadmap/24a-picture-in-picture`. Worktree: `../astra-worktrees/24a-picture-in-picture`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Astra uses WebKit-owned web video playback. Browser-level PiP controls and lifecycle behavior must be checked against the current configuration and macOS/iOS APIs.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Web/Navigation/BrowserController.swift`
- `astra/Web/Navigation/BrowserWebView.swift`
- `astra/UI/Chrome/BrowserMediaActivityView.swift`
- `astra/UI/Content/BrowserPageView.swift`
- `astra/App/AppDelegate.swift`

## Write ownership

PiP availability/configuration/control/state and tab protection hooks; minimal media-card/page/menu wiring; task-owned PiP checks and video fixture assets.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- PiP is required. Verify available WKWebView/native web-video PiP mechanisms separately for macOS and iOS; enable supported playback configuration and preserve website/native player controls. Prefer WebKit-owned playback rather than moving arbitrary web video into an app-owned AVPlayer.
- Expose a browser PiP action when a supported eligible video/control path exists. Define entering, active, restoring and ended behavior; multiple videos/tabs, iframe videos and permission/user-gesture constraints must be explicit. If a reliable programmatic command/state callback is unavailable, preserve native PiP entry and record the exact unmet browser-control requirement rather than claiming completion.
- Keep playback through tab switches, sidebar/space changes and background transitions. Protect PiP pages from destructive hibernation and accidental close/quit through known state or conservative policy. Returning from PiP focuses the originating tab/window without creating a duplicate. Close/navigation/window teardown coordinate the native session. Integrate a menu command after task 17 through a reserved AppDelegate follow-up; task 32 handles iOS scene/audio-background limits.

## Acceptance criteria

- Eligible fixture video can enter/exit PiP through the supported native path; the planned browser action has verified public capability evidence.
- Switching tabs/spaces/fullscreen/background preserves playback; restore targets the originating live tab/window and closure/quit follows documented protection.
- Unsupported/ineligible video does not expose a false enabled action. Multiple videos/windows, private sessions, iframe playback and process termination have specified outcomes.

## Verification

Add the smallest eligibility/ownership/protection check and compile PiP configuration/control code via Xcode MCP. Provide synthetic inline/iframe/multiple-video fixture cases. Actual PiP playback/restore/background checks remain pending under source/build-only verification.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

PiP is not optional. Public API limits are unresolved required capability gates, with native entry as the minimum path. DRM/provider, iOS background playback and actual lifecycle results require runtime/device evidence.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/24a-picture-in-picture.md` using the dispatch template. The primary reviews; the user merges later.
