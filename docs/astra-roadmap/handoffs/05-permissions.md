# 05 permissions handoff

Task / selected optional scope: `05-permissions`; no packet-specific optional scope.

Branch / worktree / baseline commit: `astra/roadmap/05-permissions`; `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/05-permissions`; baseline `0159f9ffdf97ef0fbafd5485adc5222d83b56d4f`.

Status: source complete; macOS build verified. iOS source is implemented but not build-verified. Runtime acceptance remains pending.

Commit(s), or explicit uncommitted state: `75905077e83a5df2ca97a1e69ed6838533e9680c` (`add scoped website permissions`). This handoff is a separate documentation checkpoint.

Changed files and behavior:

- `astra/Web/Navigation/BrowserSitePermissions.swift` adds normalized origin/top-origin decisions for Ask, Allow Once, Always Allow and Deny. Existing Boolean records migrate to the new decision format. Temporary decisions are keyed by controller, top-level navigation generation, requester origin and top origin; navigation and controller cleanup expire them. Private decisions remain in memory. Unknown or malformed future saved formats are read-only until the user explicitly resets permissions.
- `astra/Web/Navigation/BrowserWebsiteUI.swift` and `BrowserController.swift` route camera, microphone, location, iOS motion, pop-up and repeated-download prompts through the selected live controller, owning window and current document. Cancellation and stale responses do not save a decision. An explicit Don't Allow saves Deny. Existing OS authorization denial returns Deny without inventing a website decision; Not Determined is left for WebKit's system prompt.
- `Browser.swift` supplies prompt ownership for the selected tab's active controller, including the last active peek. Removed tabs, background tabs, unfocused macOS windows and inactive iOS scenes cannot keep website prompts active. JavaScript dialogs, authentication prompts, file selection, Web Push's existing experimental prompt, external-app prompts and `mailto` clipboard writes use the same ownership checks where their platform delegates exist.
- `BrowserWebSession.swift` centralizes same-session capture revocation. Permission reset stops camera and microphone capture in all normal-session windows sharing permissions, or in the owning private session. Per-site revocation compares the last committed top-site origin so a provisional URL change cannot leave existing capture running.
- `BrowserController.swift` sets WebKit's native playback policy to require user action for all audio/video. This is global; WebKit has no public per-site autoplay control. Repeated downloads use a per-controller counter that reserves attempts synchronously before asynchronous prompts or native handoffs. The first download uses WebKit's existing behavior; each later attempt uses the committed top-site permission. The counter resets only on a real document commit. Navigation-action and response decisions preserve their original callbacks; the create-window path prompts and asks the user to retry rather than replaying a canceled request.
- `BrowserSiteInformationButton.swift` and `BrowserPrivacyAndSecuritySettingsView.swift` expose supported site decisions, temporary-grant state, reset controls and current platform limits. Changes route through the shared session revocation path.
- `checks/task05-permissions-check.swift` exercises the production permission model and automatic-download policy.

Acceptance cases satisfied, with evidence:

- Origin normalization covers case folding and default/non-default ports. Decisions keep requesting origin and top origin separate. The standalone check covers cross-top-origin isolation and migration from legacy Boolean entries.
- Allow Once is held in memory and scoped to a controller and top-level navigation generation. The check proves same-document access, sibling-controller isolation, navigation expiry and no change to persisted bytes.
- Cancel maps to no stored decision; explicit Deny maps to a persistent Deny. Unknown future decision/capability values, added future fields and a malformed numeric Boolean value leave the stored bytes unchanged until explicit reset.
- Private permissions never write to the supplied defaults store. Existing per-window private sessions continue to own separate permission objects.
- Camera/microphone/location require a secure origin except loopback hosts. HTTP pop-up and repeated-download settings remain usable. macOS window/attached-sheet ownership and iOS foreground-scene ownership are checked before and after prompts.
- Capture revocation runs through the session callback for all same-session controllers. Runtime device capture and OS-authorization behavior remain pending.
- First downloads remain native. Repeated downloads through the navigation-action, response and create-window handoff routes reserve the attempt before awaiting. Conflicting site preferences use the committed top-site origin because `WKNavigationResponse` does not supply a source frame.

Checks run, scheme/destination/workspace and results:

- `swiftc astra/Web/Navigation/BrowserSitePermissions.swift checks/task05-permissions-check.swift -o /tmp/task05-permissions-check && /tmp/task05-permissions-check` passed: `Task 05 permission model checks passed`.
- `swiftc -frontend -parse astra/Web/Navigation/BrowserSitePermissions.swift astra/Web/Navigation/BrowserWebsiteUI.swift astra/Web/Navigation/BrowserController.swift astra/Web/Navigation/BrowserWebSession.swift astra/Web/Navigation/BrowserWebPushManager.swift astra/Models/Core/Browser.swift astra/UI/Chrome/BrowserSiteInformationButton.swift astra/UI/Settings/Detail/BrowserPrivacyAndSecuritySettingsView.swift checks/task05-permissions-check.swift` passed.
- `git diff --check` passed.
- Xcode MCP opened `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/05-permissions/astra.xcodeproj` as `workspace-3MHijM2I3R`, scheme `astra`, destination `My Mac`. Final build passed in 5.913 seconds. Xcode diagnostics reported zero issues in all eight changed production Swift files. The task workspace was closed afterward.
- No iOS build was run. The roadmap records the existing unrelated Sparkle import blocker; source parsing does not establish iOS type-checking or runtime behavior.

Checks written but not executed: no hosted tests or browser fixtures were executed. The task-owned pure model/policy check above was executed directly with `swiftc`.

Pending runtime/hardware/provider cases:

- Verify system camera/microphone/location prompts and denial on macOS and iOS; validate capture start, settings change/reset, and revocation across same-session tabs/windows.
- Exercise third-party iframes, same-origin iframe document replacement, queued prompts during tab/peek/window changes, and prompt dismissal exactly once. Temporary grants are scoped to the top-level document; frame identity is not separately tracked because WebKit exposes no stable frame-document token in these callbacks.
- Verify popup behavior for target-blank, script `window.open`, POST/header-sensitive popup requests and retries. `linkActivated` is the public gesture heuristic; other script-triggered popup requests are canceled, prompted, then require the page action to be retried. Native `javaScriptCanOpenWindowsAutomatically = false` still blocks calls without user activation before the delegate path.
- Verify copied `mailto` links and external-app prompts from blank tabs and Mini Astra. The new ownership guard restricts clipboard writes to the selected active controller; prompt-window availability and that compatibility boundary remain unverified for downstream window/menu/platform work in 08, 17 and 32.
- Verify first and repeated downloads, redirects, content-disposition attachments, parallel subframes and retry after Allow Once. The top-site policy intentionally avoids attributing a response to a frame WebKit does not identify. Download counts are per controller; separate tabs each receive their own first native download.
- Verify the global autoplay policy on new and already-created web views. The configuration change cannot retrofit a view already created in the current process.
- Verify iOS dialogs, file picker security-scoped URLs and motion prompts on device. The checked iOS 27 SDK declares motion permission on `WKUIDelegate` as iOS-only; the public selector used is `requestDeviceOrientationAndMotionPermissionFor`. The checked SDK does not declare `runBeforeUnloadConfirmPanelWithMessage` or a public website permission delegate for clipboard/display capture.

Migration, compatibility and private-data impact: existing `websitePermissions` Boolean records decode as Always Allow or Deny and are written in the new decision representation on the next change. Permission decisions remain device-only and are excluded from sync. Private grants are session-memory-only. Unknown or unreadable saved permission data is not replaced by an ordinary edit; the settings UI directs the user to Reset All Website Permissions before saving new decisions. No additional Defaults keys or portable sync timestamps were added.

Capability gates / unresolved issues: Web Push remains on the existing experimental private bridge and is not advertised as a public hosted capability; no private API or entitlement scope was expanded. Clipboard and display capture have no public WebKit permission delegation in the checked SDK. Motion permission is exposed on iOS only. Per-origin autoplay control is unavailable; the browser applies one global native media policy. iOS has not been type-checked by an Xcode build in this task. A stable iframe document token is unavailable in the permission delegate contract; temporary grants and stale-prompt checks use the controller's top-level document generation, so iframe-only navigation/removal needs runtime acceptance.

Merge prerequisites / follow-up ownership: task 04 is present in the baseline. The primary reviews this source and handoff before downstream packets use permission APIs. Retain all runtime and iOS build gates above.

Primary close-out: source and production model/policy checks reviewed. Final Mac build passed in5.913s with zero affected-file diagnostics. Retain the explicit iframe/native-popup/global-autoplay/iOS/runtime gates; these are not runtime acceptance. Blank-tab external app prompts and copied-mailto ownership need08/17/32 follow-up because an unmounted WebView may have no window. The user requested finishing up before any new packet; independent14 is reviewed and remains separate for combination in the next worktree.
