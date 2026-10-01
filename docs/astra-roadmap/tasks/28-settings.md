# 28-settings

Priority: P1. Status: planned. Prerequisites: 14, 18, 19, 21, 22, 24, 24a, 26, 27.
Branch: `astra/roadmap/28-settings`. Worktree: `../astra-worktrees/28-settings`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Astra has Defaults-backed settings and UI/account/privacy/extensions/advanced/about pages. Feature packets own their local keys/components; this task reconciles them.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Storage/BrowserDefaults.swift`
- `astra/UI/Settings/BrowserSettingsView.swift`
- `astra/UI/Settings/Detail/BrowserGeneralSettingsView.swift`
- `astra/UI/Settings/Detail/BrowserAdvancedSettingsView.swift`
- `astra/UI/Settings/Detail/BrowserPrivacyAndSecuritySettingsView.swift`

## Write ownership

Settings navigation/schema/reset/migrations and final feature UI wiring; preserve account/extension/theme component ownership.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete startup/homepage/new-tab, normal/private/custom search, default zoom, download location/save prompts, permission defaults, clear-data, appearance/tabs/popups/autoplay/blockers/extensions/developer/privacy settings. Include required PiP availability/control behavior; expose preferences only when useful and supported.
- Maintain one authoritative typed Defaults schema with documented defaults, migration/version policy, per-device versus synced allowlist and per-site inheritance. Reset settings is distinct from destructive browsing-data clearing; applying preferences updates relevant controllers without recreating pages or losing drafts.
- Preserve List/section/sidebar/picker/background styles and accessible controls. Disable/explain unavailable capability settings instead of displaying switches that do nothing. Keep secrets and machine paths out of exported/synced general preferences.

## Acceptance criteria

- Every selected baseline preference has a storage key, default, real effect, reset behavior and correct settings location.
- Old/future settings versions are handled safely and reset does not delete unrelated data.
- Changes propagate across appropriate windows/private scope; synced settings exclude secrets, file paths and temporary/private decisions.

## Verification

Add focused default/migration/reset/sync-allowlist checks; compile schema and relevant views. Inspect settings-to-controller application paths.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

None for the baseline scope.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/28-settings.md` using the dispatch template. The primary reviews; the user merges later.

## Required cache/update metadata

Preserve task29’s user-required local cache and timestamped merge contract. Every new synchronized entity, ordering/deletion scope and portable setting participates in persisted last-update metadata. Stamp actual local mutations, preserve remote/decoded timestamps, and verify that stale incoming data cannot replace newer local changes. Register added portable settings; retain explicit device-only exclusions.
