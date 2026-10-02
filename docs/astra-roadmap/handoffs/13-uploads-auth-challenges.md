# Task 13: Uploads and authentication challenges

Task / selected optional scope: Page-owned macOS file selection scopes; iOS native WebKit upload presentation; Basic, Digest and default authentication prompts for page and download challenges.

Branch / worktree / baseline commit: `astra/roadmap/13-uploads-auth-challenges` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/13-uploads-auth-challenges` / `83b9352`.

Status: source complete; build verification is pending the primary's serialized Xcode MCP check. Runtime, sandbox and iOS acceptance remain open.

Commit(s), or explicit uncommitted state: implementation is uncommitted. Primary requested a lowercase checkpoint using `git -c core.hooksPath=/dev/null commit` after source completion.

Changed files and behavior:

- `astra/Web/Navigation/BrowserWebsiteUI.swift`: macOS file panels now wait for an existing attached sheet to finish rather than rejecting the page's picker request. They preserve the WebKit single/multiple and directory choices, return `nil` on cancel or stale page ownership, and retain the scope the OS grants for panel-selected URLs. Stale selections stop that grant immediately. Authentication prompts identify host, non-default port and realm, warn for unencrypted connections, and return `.none` credentials. iOS uses the native WebKit upload UI so photo/camera and native drag/drop behavior remain WebKit/OS-owned; iOS page authentication now uses a serialized native alert.
- `astra/Web/Navigation/BrowserController.swift`: tracks panel-granted upload scopes for the current page and releases them at successful document commit or close. A failed provisional navigation keeps the selected file available to the still-current page. macOS and iOS page auth completion rechecks selected controller/document ownership before returning a credential.
- `astra/Web/Downloads/BrowserDownloadManager.swift`: iOS download challenges use the shared authentication presenter when the originating WebView is available. Both page and download challenge callbacks cancel if their controller/download ownership disappears while queued or presented. macOS downloads already used the shared presenter; the shared policy now applies to both.
- `astra/Web/Navigation/BrowserAuthenticationPolicy.swift`: pure challenge-method and retry decision, host/port/realm title and HTTPS classification.
- `checks/task13-auth-policy-check.swift`: production-policy check covers Basic, Digest, default, native server trust, client certificate fallback, retry boundary, realm/port and encryption classification.
- `checks/task13-upload-auth-cases.md`: representative file-selection, lifetime, native mobile upload, realm, retry, trust and download challenge cases for later runtime acceptance.

Acceptance cases satisfied, with evidence:

- macOS selected URLs are returned only after the same requesting controller and navigation generation remain current. A per-completion guard makes the panel callback exactly once, including close/navigation cancellation after the panel opens or while queued behind another sheet. The OS-granted scope is retained through a failed provisional load, then balanced at successful document commit or close. If ownership is stale when the panel returns, the panel grant is stopped immediately. Source inspection only; sandbox behavior remains unverified.
- iOS file upload remains the platform's native WebKit UI. Apple's `WKUIDelegate` documentation says iOS uploads are enabled by default when the delegate method is not implemented, preserving the system photo/camera route. Actual photo/camera, multi-select and drag/drop behavior needs iOS runtime acceptance.
- Basic/Digest/default challenges prompt at failure counts 0–2 and cancel at 3. Server-trust and client-certificate methods use default WebKit handling. The standalone production-policy check passed.
- The prompt includes host, non-default port and realm; its message clearly distinguishes HTTPS from unencrypted transport. Credentials use `URLCredential.Persistence.none`; the source contains no auth-value logging or browser persistence path.
- Page and download prompts share the existing per-window serialization path on macOS and per-window presentation queue on iOS. Source rechecks ownership after awaiting. A stale/closed challenge completes with cancellation; actual OS callback sequencing remains runtime-gated.

Checks run, scheme/destination/workspace and results:

- `swiftc astra/Web/Navigation/BrowserAuthenticationPolicy.swift checks/task13-auth-policy-check.swift -o /tmp/task13-auth-policy-check && /tmp/task13-auth-policy-check` — passed.
- `swiftc -frontend -parse` on `BrowserWebsiteUI.swift`, `BrowserController.swift`, `BrowserDownloadManager.swift` and `BrowserAuthenticationPolicy.swift` — passed. This checks syntax, not target type-checking.
- `git diff --check` — passed.
- No Xcode MCP build or diagnostics ran in this worker; the primary owns serialized Xcode checks. No app was launched, no hosted checks were executed, and no keychain or real user data was inspected.

Checks written but not executed: `checks/task13-upload-auth-cases.md` is the runtime matrix. No upload/provider fixture server was started.

Pending runtime/hardware/provider cases: signed macOS sandbox scope acquisition for NSOpenPanel URLs; scope retention while a page consumes selected files and release on navigation/close; queued panel cancellation while another alert owns the sheet; WebKit drag/drop; iOS native photo and camera capture, multi-select, cancellation and drag/drop; Basic/Digest retry behavior and realm/protocol reporting for real WebKit; cancellation during tab/window/scene changes; protected WKDownload behavior on iOS; native trust failure and real client-certificate providers.

Migration, compatibility and private-data impact: no schema, Defaults, sync, cache, download-record or project-setting change. Typed credentials are memory-only with `.none` persistence and are not logged. Selected file URLs are transient controller state; private browsing does not write them to disk. Normal and private sessions use the existing download manager/session ownership.

Capability gates / unresolved issues: Apple's public [`WKUIDelegate` upload-panel documentation](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:runopenpanelwith:initiatedbyframe:completionhandler:)) states that iOS uploads remain enabled by default without an override. Apple's [macOS sandbox standard user interactions guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox#Access-files-with-standard-user-interactions) says the system starts access for URLs selected in an open panel and the app stops it when finished; the code retains that grant without adding a second start. Actual signed sandbox behavior must still be checked. Public [`WKNavigationDelegate` challenge handling](https://developer.apple.com/documentation/webkit/wknavigationdelegate/webview(_:didreceive:completionhandler:)) exposes the challenge callback. Foundation exposes [`URLCredential` for a client identity](https://developer.apple.com/documentation/foundation/urlcredential/init(identity:certificates:persistence:)) and `NSURLAuthenticationMethodClientCertificate`, but this app has no identity-selection flow; no user keychain was inspected and no real provider was exercised. Therefore client-certificate challenges keep WebKit's default handling. Native server-trust validation remains default. Mac app type-check/build and iOS target build are pending primary Xcode MCP verification; source parsing does not establish platform availability/type-checking.

Merge prerequisites / follow-up ownership: primary review and serialized Mac Xcode MCP build are required before integration. iOS build and all listed runtime cases remain separate acceptance gates. No project, entitlement or shared roadmap file was edited.
