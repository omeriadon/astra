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
- `astra/UI/Shell/MiniAstraWindowController.swift`
- `astra/UI/Shell/MiniAstraView.swift`
- Existing settings page routing and navigation models

## Write ownership

macOS URL/default-browser/Dock/Services integration and selected automation/web-app feature files; reserved project/entitlement changes.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete default-browser/LaunchServices registration, external URL opening before/after startup, Dock commands, native sharing/Services and current window/menu correctness. Preserve Mini Astra behavior and authentication launch routing.
- If automation is selected, define supported open/create/close/list/command actions through App Intents/Shortcuts or AppleScript; validate caller parameters and restrict private/privileged access. Do not expose arbitrary webpage JavaScript execution by default.
- Standalone website Dock apps are explicitly selected and required by the user; implement the scope below. Validate any manifest metadata/icon/launch URLs used, but do not require a manifest or PWA support to install an ordinary website. Store explicit installations and define standalone window/session behavior and uninstall. Handoff/Spotlight/recent pages are optional with privacy filtering. Supported engine web app features are not automatically third-party browser installation capabilities.

## Required standalone website Dock apps

User request, recorded during packet24a: turn any website into its own standalone Dock app, reuse Mini Astra, show only the top bar by default, use Command-S to toggle that top bar, provide a settings management page, and create an app from the current tab through the macOS menu bar.

- Add an accessible menu command such as “Add Website to Dock…” for the current eligible webpage. Capture the current tab URL/title/icon as defaults, allow a name, and validate the launch URL and app name at the installation boundary. Support ordinary HTTP/HTTPS websites without requiring a manifest. Private pages must not silently export private session state or credentials.
- Produce a real launchable macOS `.app` with a stable installation identity, name and icon, LaunchServices registration, and its own Dock identity. A bookmark or a normal Astra tab does not satisfy this requirement. Validate filenames, bundle metadata and launch payloads; do not install downloaded executable code from a website.
- Launch into a dedicated single-site window using the existing Mini Astra content and top-bar implementation. Show the top bar initially, omit the regular sidebar/tab chrome, and make Command-S toggle the top bar within that standalone app. Keep the normal browser’s Command-S behavior intact. Reuse Mini Astra components without changing ordinary Mini Astra behavior incidentally.
- Keep a durable local installation registry and a dedicated settings page listing installed website apps. Provide launch, rename/update name or icon, reveal installed app, add/re-add to Dock, and uninstall/remove actions. Uninstall removes only Astra-owned installation artifacts and registry metadata, with explicit treatment of website data; never delete shared website data silently.
- Implement the concrete Dock-add path and report its actual platform mechanism. Distinguish creating/registering a launchable app, displaying its running Dock icon, and pinning it permanently. If persistent pinning has no suitable supported public API, retain a working system-assisted pinning flow and record the exact unmet automatic-pinning capability; do not imply that LaunchServices registration itself pins the app. Avoid private Dock APIs and silent Dock preference rewriting.
- Installation artifacts, executable paths, bundle registrations and Dock position are device-only cached state. Persist update timestamps for editable registry metadata; decode and read do not invent freshness. Any metadata later selected for sync joins the existing timestamped merge/tombstone contract, while local executable paths and credentials remain excluded.
- Define session/cookie ownership, external links, authentication, multiple app instances, relaunch, missing installation files and upgrade behavior. Preserve the browser’s existing session and security boundaries; do not invent a new profile system in this packet. Carry forward media/PiP teardown protection when reusing Mini Astra.

## Acceptance criteria

- Cold/warm external URL launches and default-browser status use the proper current session/window.
- Dock/Services/menu actions work from valid state and omit private data.
- Selected automation/installed-site integrations validate origins/metadata, preserve privacy and use honest supported platform behavior.
- A website without a manifest installs as a launchable app with its own Dock identity; cold/warm launch opens the saved website in Mini Astra-style standalone chrome. Command-S toggles only that app’s top bar.
- The current-tab menu command and settings management page cover create, launch, update, reveal, Dock-add and uninstall; duplicate names, invalid URLs, moved/deleted bundles and relaunch have defined outcomes.

## Verification

Add URL launch/manifest/caller-filter checks for changed logic; compile. Add focused installation registry, name/path/launch-payload validation and update/delete checks. Compile standalone app generation/launch wiring and settings/menu code through Xcode MCP. Write cold/warm launch, distinct Dock identity, permanent pinning, Command-S, management and uninstall acceptance cases. LaunchServices/Dock/Services/Shortcuts/standalone window behavior remains pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Standalone website Dock apps are selected and required. App generation/signing, sandbox installation access, independent Dock identity and permanent pinning need precise API/configuration evidence. Automation, Handoff and Spotlight retain their selected scope and API/configuration gates; no legacy Touch Bar work unless explicitly selected.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/31-macos-automation-webapps.md` using the dispatch template. The primary reviews; the user merges later.
