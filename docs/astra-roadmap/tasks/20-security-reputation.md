# 20-security-reputation

Priority: P0 baseline; P2 added provider. Status: planned. Prerequisites: 02, 05, 06, 18.
Branch: `astra/roadmap/20-security-reputation`. Worktree: `../astra-worktrees/20-security-reputation`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Controller already tracks committed URL/secure content and provides connection descriptions. Native fraudulent-site warnings and permission UI are configured.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/UI/Chrome/BrowserSiteInformationButton.swift`
- `astra/Web/Navigation/BrowserController.swift`
- `astra/UI/Content/BrowserNavigationErrorView.swift`
- `astra/Web/Navigation/BrowserSitePermissions.swift`

## Write ownership

Security state/panel/interstitial UI and policy hook; additional reputation service files only after the provider gate.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Present committed-origin HTTPS/HTTP/local/mixed-content/failure state accurately; do not infer safety from the typed or provisional address. Certificate detail is offered only from supported evidence. Active camera/microphone/location/display sharing indicators remain distinct from saved permission grants.
- Preserve WebKit trust enforcement and native fraud warnings. If an additional reputation provider is selected, specify license/key provisioning, query privacy, disclosure, cache TTL, failure/offline policy and explicit override before implementation.
- A browser-owned phishing/malware warning binds to destination/document/session and cannot be forged by a page. Overrides are limited and deliberate; never bypass TLS/certificate validation through a generic security setting.

## Acceptance criteria

- Redirects/errors cannot leave a prior HTTPS/security badge attached to another origin.
- Permission-active indicators show known state and distinguish unknown/unavailable capture data.
- Selected reputation integration has bounded requests/cache, a safe stale-response policy and interstitial/override behavior; absent provider leaves native protections working.

## Verification

Add committed-state/interstitial generation/override checks if changed; compile. Use synthetic malicious-site results, not live dangerous pages.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Additional Safe Browsing/reputation is optional. Provider choice, credentials, privacy terms and supported certificate/capture data are explicit gates.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/20-security-reputation.md` using the dispatch template. The primary reviews; the user merges later.
