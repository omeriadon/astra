# 34-diagnostics-performance

Priority: P1. Status: planned. Prerequisites: 06, 12, 22, 24, 24a, 29.
Branch: `astra/roadmap/34-diagnostics-performance`. Worktree: `../astra-worktrees/34-diagnostics-performance`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

BrowserDiagnostics provides explicit redacted diagnostic copying. Prewarming, lazy views, snapshot throttling and background persistence already exist.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/App/BrowserDiagnostics.swift`
- `astra/Web/Navigation/BrowserController.swift`
- `astra/App/AppDelegate.swift`
- `astra/Storage/FaviconStore.swift`
- `astra/Web/Downloads/BrowserDownloadManager.swift`
- `docs/desktop-browser-infrastructure.md`

## Write ownership

Diagnostics/export and minimal measurement instrumentation; performance changes only for identified evidence-backed costs.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Capture app/WebContent crashes, navigation/download/extension failures and explicit debug export using bounded categories/version/OS/engine data. Omit URLs, query strings, tokens, passwords, form/page content and private metadata. No telemetry backend unless selected.
- Define reproducible startup/tab-switch/memory-per-tab baselines and large-tab/slow-page scenarios. Instrument existing hot paths minimally; measure before changing pooling/prewarming/caches or adding a live-view cap. Preserve PiP/capture/drafts in every optimization.
- Bound owned previews/favicon data and confirm background persistence is off view hot paths. Compatibility fixes/UA overrides require a concrete affected site, rationale, expiry and regression case. Do not gather page contents to diagnose pathologies by default.

## Acceptance criteria

- Diagnostics contain only approved fields; synthetic secrets/private URLs fail a redaction/allowlist check.
- Metrics specify device/OS/build/tab count/measurement method and compare like-for-like; unexecuted baselines are labeled pending.
- Any optimization has evidence and preserves lifecycle/privacy/PiP invariants; speculative tuning is left as a measured follow-up.

## Verification

Add diagnostic allowlist/size-limit checks; compile. Runtime Instruments/timing/memory and real crash collection remain pending under current restrictions.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Telemetry is optional. Performance improvement claims require measurements; source inspection alone cannot provide timing or memory results.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/34-diagnostics-performance.md` using the dispatch template. The primary reviews; the user merges later.
