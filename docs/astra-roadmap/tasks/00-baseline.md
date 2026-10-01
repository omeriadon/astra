# 00-baseline

Priority: P0. Status: planned. Prerequisites: None.
Branch: `astra/roadmap/00-baseline`. Worktree: `../astra-worktrees/00-baseline`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Astra already has the main browser services, atomic snapshots, private sessions, native extension hosting and sync. The project references a test target, but its source and earlier fixture/release pipeline files are absent at final planning validation. Historical research includes findings that have since been addressed.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `docs/desktop-browser-infrastructure.md`
- `docs/desktop-release.md`
- `astra.xcodeproj/project.xcproj`
- `astra.xcodeproj/xcshareddata/xcschemes/astra.xcscheme`

## Write ownership

docs/astra-roadmap/contracts.md and capabilities.md (new task outputs); only necessary project/test-membership corrections reserved by the primary.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Inventory current behavior against the roadmap. Record the committed implementation baseline, app/test schemes, deployment targets and SDK. Confirm tab/window/session ownership and preserve the existing normal-window sharing and independent-private-window semantics.
- Separate code already implemented from observed gaps and unverified runtime behavior. Produce a compact capability ledger for Web Push, passkeys/AutoFill, client certificates, screen capture, native restoration, PiP, audio/mute state, spatial output, content blockers, extensions, sandboxed file access and Sparkle installation. Verify uncertain API facts through installed SDK/Xcode documentation and current primary sources; cite platform availability. Record supported, unavailable, conditional and unverified separately.
- Reserve the next packet's files. Reconcile project/test-scheme references with the absent test sources. Inventory missing historical fixture and release assets without automatically restoring them. Select only the smallest verification asset needed by actual implementation; confirm any retained test-host startup protections. Repair only blockers needed to dispatch the roadmap; do not reorganize the app.

## Acceptance criteria

- A baseline commit and source inventory are recorded; no old finding is relabeled as a current defect without checking source.
- Every unresolved capability has an owner, evidence and a next acceptance step. Required PiP remains required if feasibility is unresolved.
- Contracts state where new services attach and what must remain unchanged, without speculative interfaces.

## Verification

Source inspection; Xcode MCP diagnostics/build only for a changed project or actual compiler uncertainty. Existing tests/fixtures remain unexecuted.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

None for the baseline scope.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/00-baseline.md` using the dispatch template. The primary reviews; the user merges later.
