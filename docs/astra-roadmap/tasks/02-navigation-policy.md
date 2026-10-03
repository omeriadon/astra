# 02-navigation-policy

Priority: P0. Status: planned. Prerequisites: 01.
Branch: `astra/roadmap/02-navigation-policy`. Worktree: `../astra-worktrees/02-navigation-policy`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Controller delegates already route normal links, modifier gestures, new contexts, downloads and external-app prompts. Universal links currently use WebKit’s native allow path.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/Web/Navigation/BrowserController.swift`
- `astra/UI/AddressBar/BrowserAddress.swift`
- `astra/Models/Core/Browser.swift`
- `astra/Web/Navigation/BrowserNavigationFailure.swift`
- `docs/web-push-and-app-links.md`

## Write ownership

Navigation-policy and popup/external-link sections of BrowserController.swift; routing hooks in Browser.swift; scheme classification in BrowserAddress.swift.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Apply one coherent policy across typed/opened URLs, links, redirects, frames, target=_blank and JavaScript windows. Preserve original requests, headers, POST bodies, popup configurations, opener behavior and explicit foreground/background tab gestures.
- Define popup defaults, user-gesture behavior and per-site override hookup. Route mailto/tel/sms/facetime/maps/music/itms-apps/system-preferences/custom schemes through validated OS handoff, identifying the requesting origin and receiving app. Preserve the existing mailto-copy preference. Rate-limit repeated launch requests and cancel queued launches when ownership changes.
- Keep universal-link website fallback and tab gestures intact. Classify unsupported engine URLs as download, external handoff or visible failure. Route browser-owned URLs only through the later trusted internal router.

## Acceptance criteria

- Normal, new-context and modifier clicks produce the intended tab/window behavior; POST/opener flows are not converted into URL-only loads.
- A missing app, canceled prompt, navigation or closed tab cannot launch a queued external URL; callbacks complete once.
- Engine schemes stay in WebKit; internal/unsafe schemes cannot acquire privileges through generic external routing.

## Verification

Use decision-table tests for policies and scheme/gesture classification; compile them. Add fixture cases for POST, opener, redirects, repeated launches and universal-link fallback.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Custom universal-link stay/open/ask controls require supported APIs. Preserve the working native behavior if finer control is unavailable.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/02-navigation-policy.md` using the dispatch template. The primary reviews; the user merges later.
