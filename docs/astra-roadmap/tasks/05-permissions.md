# 05-permissions

Priority: P0. Status: source reviewed; Mac build verified; runtime/API gates remain. Prerequisites: 04.
Branch: `astra/roadmap/05-permissions`. Worktree: `../astra-worktrees/05-permissions`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

BrowserSitePermissions stores camera/microphone/location decisions keyed by requesting and top origin. WebsiteUI orders prompts and the site/settings panels expose decisions.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Web/Navigation/BrowserSitePermissions.swift`
- `astra/Web/Navigation/BrowserWebsiteUI.swift`
- `astra/Web/Navigation/BrowserController.swift`
- `astra/UI/Chrome/BrowserSiteInformationButton.swift`
- `astra/UI/Settings/Detail/BrowserPrivacyAndSecuritySettingsView.swift`
- `docs/web-push-and-app-links.md`

## Write ownership

Permission model/prompt paths and permission UI; permission defaults keys reserved in BrowserDefaults.swift; task-owned capability checks.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Define ask/temporary allow/persistent allow/deny/default behavior and migration of existing Boolean entries. Normalize scheme/host/port, separate embedded origin from top origin and preserve private isolation.
- Cover camera, microphone, location, popups, automatic multiple downloads and autoplay. For website notifications/Web Push, clipboard, screen/display capture and motion sensors, identify supported delegation/system gates before implementing controls. Do not substitute browser-native notifications for web push.
- Prompts identify the website/capability, respect OS authorization, serialize, and cancel cleanly after navigation/close. Settings permit change/reset and stop active capture where supported. Expose only known active-permission state; integrate hooks for downloads and navigation.

## Acceptance criteria

- Origin/port/frame scoping and temporary versus persistent decisions work without private persistence.
- A canceled/stale prompt is not stored as Deny; every decision callback completes once.
- Reset/change applies across same-session tabs/windows, and unsupported capabilities have honest recorded limits.

## Verification

Add permission-scoping/migration/temporary-decision checks; compile. Record concurrent prompt, OS-denial, iframe and capture-revocation fixture cases.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

The current Web Push assessment records a public host/authorization ceiling; do not substitute native notifications or retry private APIs. Recheck only when relevant SDK/API conditions change. Clipboard, display capture and sensor hosting are capability gates; unsupported controls cannot imply granted website access.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/05-permissions.md` using the dispatch template. The primary reviews; the user merges later.
