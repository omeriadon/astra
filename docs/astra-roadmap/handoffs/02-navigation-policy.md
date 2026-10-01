# 02-navigation-policy handoff

Task / selected optional scope: 02-navigation-policy; baseline navigation and external-scheme policy. Per-origin popup settings remain with task 05.
Branch / worktree / baseline commit: `astra/roadmap/02-navigation-policy`; `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/02-navigation-policy`; `7b8ced584d78da719a2fa1b08576d9d79f62c7e7`.
Status: build verified; parser follow-up compiled with a pure Foundation check.
Commit(s), or explicit uncommitted state: included in the `add navigation scheme policy` checkpoint and `fix address host port parsing` follow-up.

## Changed files and behavior

- `astra/Web/Navigation/BrowserNavigationPolicy.swift` centralizes restricted-scheme exclusions for external dispatch; exclusions do not claim that WebKit renders those schemes.
- `astra/UI/AddressBar/BrowserAddress.swift` reuses that classifier and accepts external application URLs as explicit address input. It resolves bare hostname/localhost ports before opaque custom schemes and rejects invalid ports; `mailto:` and custom schemes remain intact.
- `astra/Web/Navigation/BrowserController.swift` routes typed and WebKit-originated external URLs through the same handoff; macOS prompts name both requesting origin and receiving app, stale prompts cancel on document change or controller close, and repeated requests are throttled. iOS uses public `UIApplication.open` with completion feedback but launches without a browser confirmation.
- `checks/task02-navigation-policy-check.swift` checks known external schemes, restricted exclusions, typed address parsing, hostname/localhost ports, invalid ports, mailto and custom schemes using the actual Foundation helper and parser.

## Acceptance cases and verification

- Scheme classification and typed input cases pass in the standalone check.
- `swiftc -frontend -parse` passed for the changed controller, classifier, address parser and check source.
- Follow-up check covers `localhost:8765`, `localhost:8765/path`, `example.com:8443/path`, alphabetic and out-of-range ports, `mailto:person@example.com`, and opaque/hierarchical custom schemes.
- Standalone command passed: `swiftc -o /tmp/task02-navigation-policy-check astra/Web/Navigation/BrowserNavigationPolicy.swift astra/UI/AddressBar/BrowserAddress.swift astra/UI/AddressBar/AddressDisplayStyle.swift checks/task02-navigation-policy-check.swift && /tmp/task02-navigation-policy-check`.
- Xcode MCP opened `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/02-navigation-policy/astra.xcodeproj` as workspace `workspace-eAv1gawPdO`, scheme `astra`, destination `My Mac`; app build succeeded with no reported errors.
- `XcodeRefreshCodeIssuesInFile` failed for all three changed product files with Xcode `SourceEditor.SourceEditorCallableDiagnosticError error 5`; the successful full app build is the compiler evidence.
- No app, hosted tests, browser fixtures or receiving applications were launched.

## Pending cases and limits

- Runtime acceptance remains pending for POST/new-window/opener behavior, modifier gestures, JavaScript `window.open`, WebKit redirects/frames, universal-link fallback, missing/canceled external apps, repeated prompts and launch failure.
- Prompt cancellation detects navigation, controller invalidation and window closure. Selected-tab ownership integration is assigned to task 05.
- iOS currently launches through public `UIApplication.open` without browser confirmation. Task 32 owns a generic requesting-origin/scheme confirmation; public iOS APIs do not expose the receiving app identity to Astra. macOS identifies the app before prompting.
- Popup auto-open remains disabled by default for newly created sessions. Per-origin popup preference storage/UI is deferred to task 05 as assigned; no future stub was added.
- Universal-link websites retain WebKit's native `.allow` path and website fallback. No custom stay/open/ask controls were added.

Migration, compatibility and private-data impact: none. No persistence, sync, schema, project, or entitlement changes.
Capability gates / unresolved issues: iOS receiving-app identity is unavailable through the used public handoff API; actual installed-app and universal-link behavior requires runtime acceptance.
Merge prerequisites / follow-up ownership: task 01 baseline is present; task 05 owns selected-tab prompt ownership and per-origin popup preference integration; task 32 owns iOS confirmation. No push or merge performed.
