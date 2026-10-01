# 26-reader-translation-source

Priority: P2. Status: planned. Prerequisites: 16, 18, 25.
Branch: `astra/roadmap/26-reader-translation-source`. Worktree: `../astra-worktrees/26-reader-translation-source`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Source export exists. No source inspection performed for this roadmap establishes a complete reader/translation engine; these are selected presentation features.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Web/Navigation/BrowserDesktopCommands.swift`
- `astra/Web/Navigation/BrowserController.swift`
- `astra/UI/Content/BrowserPageView.swift`
- `astra/UI/Settings/Detail/BrowserAdvancedSettingsView.swift`

## Write ownership

Feature-owned reader/translation/source UI and minimal reserved controller/per-site hooks.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- If reader mode is selected, define supported detection/extraction, original/reader transitions, text/appearance preferences and per-site defaults. Use a maintained installed/native mechanism if available before adding dependencies; transforming content needs origin/resource safety.
- If translation is selected, define provider, language detection, disclosure/network privacy, original/translated state, failure/revert and per-language preferences. Keep credentials/private page content out of unapproved remote requests.
- For selected view-source support, route the action to a read-only source viewer with copy/save and optional native/simple highlighting. Source is displayed as text and cannot execute. Do not confuse fetching a new URL with the exact authenticated/POST document source.

## Acceptance criteria

- Each selected feature has capability/provider evidence, bounded content handling and a working original/revert path.
- Source/translated/reader content cannot acquire browser privileges or leak private text to an unapproved service.
- Preferences persist in the correct scope; unsupported pages/actions produce a clear disabled/failure state.

## Verification

Add text/escaping/generation/privacy checks for selected logic; compile. Reader fidelity/translation/provider/source-document cases remain pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Reader and translation are optional provider/capability gates; source viewer is optional beyond existing source export.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/26-reader-translation-source.md` using the dispatch template. The primary reviews; the user merges later.
