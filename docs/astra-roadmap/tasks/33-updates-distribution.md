# 33-updates-distribution

Priority: P0 release. Status: planned. Prerequisites: 28, 31, 32.
Branch: `astra/roadmap/33-updates-distribution`. Worktree: `../astra-worktrees/33-updates-distribution`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Sparkle configuration and UpdateManager exist. The release document describes Developer ID signing, notarization and updater validation, but its historical workflow/scripts are absent from the current checkout. Prior Xcode integration rejected some entitlements; recheck current configuration before treating them as active blockers.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/App/UpdateManager.swift`
- `astra/UI/Settings/Detail/Update/`
- `astra/Special/Info.plist`
- `astra/Special/astra.entitlements`
- `astra.xcodeproj/project.xcproj`
- `docs/desktop-release.md`

## Write ownership

Updater UI/configuration and release documentation; release validation/workflows are new files only if the selected distribution scope requires them. Credentials/publication are outside implementation authorization.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete update checking, feed/version/build semantics, background/automatic preference behavior, signed download verification and restart/install UX through Sparkle. Do not implement an updater/signature verifier from scratch.
- Resolve documented sandbox installer/file-bookmark capability problems through supported Xcode configuration and signed-artifact evidence. Keep validation fail-closed when required capabilities/signatures/notarization are absent. Distinguish missing credentials from code defects without repeated unchanged retries.
- Document older-to-newer signed update, cancellation/failure/invalid-signature behavior and preserving app/browser data. Recovery/rollback must match actual distribution support; do not promise downgrade across incompatible schemas. iOS updates remain App Store/platform-owned. No push, publication, secret creation or update installation is performed by this packet.

## Acceptance criteria

- Feed/key/version/configuration validation catches invalid inputs and UI reflects real updater state.
- Unsigned/missing-capability artifacts cannot pass selected release validation; distribution secret handling avoids logs, shell interpolation and persistent credential artifacts.
- Signed-update/Gatekeeper/notarization acceptance cases are specified and unresolved credentials/capabilities are concrete release blockers.

## Verification

Inspect current Xcode configuration and any distribution assets available at dispatch time. Add/run only a needed non-app artifact validation check within selected release scope; Xcode MCP build only when required. Signed installation/update/publication remains pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Release credentials, rejected entitlements, notarization and sandboxed signed update installation remain external/runtime gates. Do not publish from an implementation branch.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/33-updates-distribution.md` using the dispatch template. The primary reviews; the user merges later.
