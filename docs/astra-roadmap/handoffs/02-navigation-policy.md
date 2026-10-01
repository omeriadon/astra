# 02-navigation-policy handoff

Task / selected optional scope: 02-navigation-policy; baseline navigation and external-scheme policy. Per-origin popup settings remain with task 05.
Branch / worktree / baseline commit: `astra/roadmap/02-navigation-policy`; `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/02-navigation-policy`; `7b8ced584d78da719a2fa1b08576d9d79f62c7e7`.
Status: build verified.
Commit(s), or explicit uncommitted state: included in the `add navigation scheme policy` checkpoint.

## Changed files and behavior

- `astra/Web/Navigation/BrowserNavigationPolicy.swift` centralizes browser/engine scheme exclusions for external dispatch.
- `astra/UI/AddressBar/BrowserAddress.swift` reuses that classifier and accepts external application URLs as explicit address input; unsafe and engine schemes remain search input or WebKit-owned.
- `astra/Web/Navigation/BrowserController.swift` routes typed and WebKit-originated external URLs through the same handoff; macOS prompts name both requesting origin and receiving app, stale prompts cancel on document change or controller close, and repeated requests are throttled. iOS uses public `UIApplication.open` completion feedback. Default-created WebViews keep automatic script popups disabled; supplied popup configurations and original request callbacks remain intact.
- `checks/task02-navigation-policy-check.swift` checks known external schemes, engine/internal exclusions and typed address parsing using the actual Foundation helper.

## Acceptance cases and verification

- Scheme classification and typed input cases pass in the standalone check.
- `swiftc -frontend -parse` passed for the changed controller, classifier, address parser and check source.
- Standalone command passed: `swiftc -o /tmp/task02-navigation-policy-check astra/Web/Navigation/BrowserNavigationPolicy.swift astra/UI/AddressBar/BrowserAddress.swift astra/UI/AddressBar/AddressDisplayStyle.swift checks/task02-navigation-policy-check.swift && /tmp/task02-navigation-policy-check`.
- Xcode MCP opened `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/02-navigation-policy/astra.xcodeproj` as workspace `workspace-eAv1gawPdO`, scheme `astra`, destination `My Mac`; app build succeeded with no reported errors.
- `XcodeRefreshCodeIssuesInFile` failed for all three changed product files with Xcode `SourceEditor.SourceEditorCallableDiagnosticError error 5`; the successful full app build is the compiler evidence.
- No app, hosted tests, browser fixtures or receiving applications were launched.

## Pending cases and limits

- Runtime acceptance remains pending for POST/new-window/opener behavior, modifier gestures, JavaScript `window.open`, WebKit redirects/frames, universal-link fallback, missing/canceled external apps, repeated prompts and launch failure.
- WebKit exposes no selected-tab ownership callback in the owned controller boundary. Prompt cancellation detects navigation, controller invalidation and window closure; switching to another still-mounted tab cannot be detected without a later Browser routing integration.
- iOS public `UIApplication.open` reports success or failure but does not identify the receiving app to Astra. macOS identifies the app before prompting. iOS app identity/confirmation is an API limitation of this implementation.
- Popup auto-open remains disabled by default for newly created sessions. Per-origin popup preference storage/UI is deferred to task 05 as assigned; no future stub was added.
- Universal-link websites retain WebKit's native `.allow` path and website fallback. No custom stay/open/ask controls were added.

Migration, compatibility and private-data impact: none. No persistence, sync, schema, project, or entitlement changes.
Capability gates / unresolved issues: iOS receiving-app identity and tab-switch prompt ownership above; actual installed-app and universal-link behavior requires runtime acceptance.
Merge prerequisites / follow-up ownership: task 01 baseline is present; task 05 owns per-origin popup preference integration. No push or merge performed.
