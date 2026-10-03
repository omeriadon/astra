# 14-address-search-config

Priority: P1. Status: source reviewed; Mac build verified before final parser guard; current helper checks pass; runtime gates remain. Prerequisites: 04.
Branch: `astra/roadmap/14-address-search-config`. Worktree: `../astra-worktrees/14-address-search-config`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

BrowserAddress uses URLComponents, trims input, defaults omitted schemes to HTTPS and falls back to Google. Google-specific display/query/suggestion assumptions also exist in search models.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/UI/AddressBar/BrowserAddress.swift`
- `astra/UI/AddressBar/BrowserAddressField.swift`
- `astra/Models/Search/BrowserSearch.swift`
- `astra/Models/Search/BrowserSearchSuggestions.swift`
- `astra/Storage/BrowserDefaults.swift`

## Write ownership

Address parsing/display and search engine configuration/suggestion transport; feature settings component and defaults keys.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Define URL/query classification for explicit schemes, host/path, localhost, IPv4/IPv6/ports, whitespace, pasted wrappers and malformed input. Normalize conservatively; retain meaningful query/fragment/percent encoding and never execute pasted javascript or privileged URLs accidentally.
- Add normal/default/private search engine choice, bounded custom templates and search keyword shortcuts. Generate queries with URLComponents and support provider-aware display rather than Google-specific labels. Suggestions use the configured provider only when enabled, with private-mode policy, cancellation, timeouts and response limits.
- Keep HTTP handling compatible with the existing HTTPS-first navigation policy. Site search-engine discovery is delegated to task 15's optional gate.

## Acceptance criteria

- A classification table covers malformed/scheme-less/local/Unicode/encoded addresses and queries without crashes or accidental executable routing.
- Engine changes affect address and new-tab searches/display together; Unicode and reserved query characters encode correctly.
- Disabled/private-policy suggestions send no forbidden requests and stale provider/query responses are ignored.

## Verification

Add table-driven parsing/template/provider tests with no external network; compile. Inspect every BrowserAddress caller before changing its result contract.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

None for the baseline scope.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/14-address-search-config.md` using the dispatch template. The primary reviews; the user merges later.
