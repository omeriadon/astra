# 18-site-data-preferences

Priority: P1. Status: source complete, independently reviewed and Mac build verified; runtime gates remain open. Prerequisites: 03, 04, 05, 09, 16.
Branch: `astra/roadmap/18-site-data-preferences`. Worktree: `../astra-worktrees/18-site-data-preferences`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Privacy settings already enumerate WebKit website-data records, remove a site/all data and show permissions. HTTPS-first/GPC preferences exist; per-site behavior is fragmented.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/UI/Settings/Detail/BrowserPrivacyAndSecuritySettingsView.swift`
- `astra/Web/Navigation/BrowserWebSession.swift`
- `astra/Web/Navigation/BrowserSitePermissions.swift`
- `astra/Web/Navigation/BrowserController.swift`
- `astra/Storage/BrowserDefaults.swift`

## Write ownership

Website-data UI/session clearing and per-site preference model/store; preference application hooks and settings components.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete site/global clearing and last-hour/today/all-time choices, separating history from website storage. Use WebKit records/types/date APIs and disclose actual granularity; do not imply exact per-cookie/per-origin/time deletion where the API cannot provide it. Clear owned favicon/derived data as applicable.
- Persist canonical-origin zoom, desktop/mobile mode, autoplay/popups, content exceptions, reader/site appearance and UA overrides only for selected supported features. Define default inheritance/reset and private temporary behavior. Apply changes across same-session tabs without unsolicited reload/data loss.
- Maintain sparse, evidence-based compatibility overrides with rationale/expiry, developer custom UA and restore-default behavior. Optional tracking-parameter stripping uses a narrow reviewed list and preserves signed/authentication URLs; fingerprint/referrer changes stay within supported WebKit semantics.

## Acceptance criteria

- Clear operations delete the documented types/range, refresh UI and do not resurrect history from backups.
- Origin/default/reset handling is deterministic and private preferences remain ephemeral.
- Per-site zoom/UA/autoplay/exceptions affect the correct session/documents; reset restores native/default behavior without affecting unrelated sites.

## Verification

Add origin/default/time-range/migration preference checks; compile. Storage clearing, compatibility and privacy behavior remain fixture/runtime cases.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Exact website-data granularity, privacy overrides and UA modes depend on APIs. Tracking stripping/fingerprinting/referrer changes are optional and require demonstrated compatibility.

Selected implementation: time-range and grouped-record WebKit storage removal, wholesale owned favicon-cache clearing, synchronized per-origin zoom, device-only per-origin desktop/mobile and custom UA choices, and the existing per-origin popup permission flow. Per-origin autoplay remains unavailable through the current web-view configuration without replacing a live page. Reader/site appearance controls are not exposed by the current site UI. Content-blocking exceptions remain gated on packet21's blocker owner. Tracking-parameter stripping remains optional and unimplemented.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/18-site-data-preferences.md` using the dispatch template. The primary reviews; the user merges later.
