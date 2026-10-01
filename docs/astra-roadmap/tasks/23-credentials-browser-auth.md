# 23-credentials-browser-auth

Priority: P0 / P1. Status: planned. Prerequisites: 13.
Branch: `astra/roadmap/23-credentials-browser-auth`. Worktree: `../astra-worktrees/23-credentials-browser-auth`.

Read [the roadmap](../README.md) and [dispatch procedure](../dispatch.md). Implement only this packet's selected scope, using its own worktree and reserved files. No implementation starts from this document alone.

## Existing baseline

Astra already advertises and implements a macOS browser authentication-session handler, ephemeral sessions, callback matching and initial header behavior.

## Source entry points

Paths are relative to the repository root. Read current implementations and callers before editing.

- `astra/App/BrowserAuthenticationSessionHandler.swift`
- `astra/App/AppDelegate.swift`
- `astra/Special/Info.plist`
- `astra/Web/Navigation/BrowserController.swift`

## Write ownership

Authentication-session handler/capability configuration and native credential integration hooks; Xcode entitlement/plist changes explicitly reserved.

Reserve shared-file edits through the primary before starting. Add unique tests/fixtures rather than competing for the existing harness files. Other packets' files are read-only unless the primary assigns a necessary integration change.

## Implementation

- Complete requesting-app authentication launch, HTTPS/custom callbacks, cancellation, initial headers and ephemeral browser-session cleanup. Revalidate callback scheme/host/path and session ownership against the public API contract; avoid capturing unrelated navigations.
- Verify third-party browser AutoFill, passkeys, system credential suggestions and strong-password hooks on each target. Add only supported native integration/associated-domain configuration and useful user settings; preserve WebKit credential UI.
- Keep website credentials distinct from Astra sync/account sign-in. Never store page passwords in sync/session/history/diagnostics. Basic/Digest handling remains with task 13 and native trust handling. Record provider-specific compatibility acceptance rather than pretending successful compilation proves sign-in.

## Acceptance criteria

- Canceled/expired/closed authentication sessions cannot deliver a later callback; matching rejects unrelated URLs.
- Ephemeral auth neither reuses normal cookies nor leaves restored private pages.
- Credential support has SDK/configuration evidence and pending provider cases; unavailable hooks do not produce custom password storage or a fake passkey flow.

## Verification

Add callback-matching/session invalidation checks; compile with required Xcode config diagnostics. Provider/AutoFill/passkey ceremonies remain pending.

The Browser project permits source inspection and Xcode MCP diagnostics/builds when needed. App operation and hosted test execution remain pending. Report source/build evidence separately from runtime acceptance. Preserve the user's SwiftUI conventions and accessibility in every changed view.

## Gates and exclusions

Real requesting-app/provider tests and Apple capability/associated-domain requirements are unresolved runtime/configuration gates.

Preserve unrelated architecture, formatting and user changes. No pushes, merges, repository-specific agent instructions or speculative dependencies.

## Handoff

Return changed files, selected scope, completed checks, pending cases, data/privacy/migration impact and unresolved issues. Write `docs/astra-roadmap/handoffs/23-credentials-browser-auth.md` using the dispatch template. The primary reviews; the user merges later.
