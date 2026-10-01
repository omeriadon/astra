# 35-accessibility-integration

Priority: P0 release. Status: planned. Prerequisites: all-selected.
Branch: `astra/roadmap/35-accessibility-integration`. Worktree: `../astra-worktrees/35-accessibility-integration`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Feature packets carry their own accessibility/check requirements. Historical hosted tests and browser fixtures are documented as compiled but unexecuted; their source files are absent at final planning validation. Review the verification assets actually available after task 00 and subsequent implementation.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/UI/`
- `astra/App/AppDelegate.swift`
- `astra.xcodeproj/xcshareddata/xcschemes/astra.xcscheme`
- `docs/desktop-release.md`

## Write ownership

Focused accessibility/integration corrections and final acceptance ledger, including task handoffs and check assets created during implementation; no unrelated visual refactor or feature additions.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Reconcile every selected packet and capability decision against the checklist. Review merged source for stable tab/session ownership, migration safety, stale prompt/callback cancellation, normal/private separation and consistency of settings/commands.
- Audit browser VoiceOver labels/actions/focus order, keyboard-only navigation, contrast, text scaling, reduced motion and meaningful loading/error/download announcements. Webpage accessibility remains WebKit's responsibility. Apply focused fixes to actual integration/accessibility defects.
- Compile relevant targets/checks with Xcode MCP and record pending runtime/device/hardware/provider tests. Required PiP matrix covers enter/exit, restore focus, tab/space/window switches, close/quit, hibernation, private/iframe/multiple videos, fullscreen, process failure and iOS scene/background transitions.
- Produce a release-readiness ledger: source/build evidence, runtime cases still unexecuted, capability limitations and external signing/provider gates. No app operation, fake pass status, release push or deployment.

## Acceptance criteria

- Every selected checklist area maps to an integrated packet or an explicit unresolved gate with ownership.
- Merged diagnostics/build results and privacy/migration/accessibility source review are recorded; no packet result is lost in conflicts.
- PiP and all required runtime/hardware/signed-update cases remain release blockers until actually verified, with exact cases/evidence required.

## Verification

Run only permitted source inspections and Xcode MCP diagnostics/builds as justified by integrated changes. Compile meaningful checks; do not execute hosted tests or launch the app. Hand the runtime matrix to the user for later authorized execution.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Current source/build-only restriction prevents full runtime certification. Release readiness stays incomplete until required device/provider/hardware/update cases pass.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/35-accessibility-integration.md` using the dispatch template. The primary reviews; the user merges later.
