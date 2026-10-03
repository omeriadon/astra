# 24a Picture in Picture

Task / selected optional scope: WebKit-owned HTML video PiP controls and protection across browser lifecycle. The minimal Navigation menu action was added because prerequisite packet 17 is absent; no other packet-17 work was included.

Branch / worktree / baseline commit: `astra/roadmap/24a-picture-in-picture` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/24a-picture-in-picture` / `a9ba5cbb38c82dd9c00c480593adaa1b565b37b7`.

Status: source reviewed and Mac build verified; capability and runtime gates remain open.

Commit(s): `0322585358fe2567fb8ff47155187b3225939323` (implementation, fixtures and checks).

Changed files and behavior:

- `astra/Web/Navigation/BrowserController.swift` keeps media in WebKit, configures iOS PiP playback, detects eligible main-frame video through standard and WebKit presentation-mode APIs, invokes the WebKit DOM action, reports failed attempts in the session toast, and coordinates native media close on navigation or teardown.
- `astra/Web/Navigation/BrowserPictureInPicturePolicy.swift` centralizes the transient media protection rule. Playing, paused, entering, or active media prevents hibernation and triggers a destructive-close confirmation.
- `astra/UI/Chrome/BrowserMediaActivityView.swift` and `astra/App/AppDelegate.swift` expose accessible page-card and macOS Navigation menu actions for eligible video and return to the source.
- `astra/UI/Content/BrowserContentView.swift`, `astra/UI/Content/BrowserPageView.swift`, `astra/UI/Peeks/PeekStackView.swift`, and `astra/UI/Peeks/PeekCardView.swift` retain the selected and recent web views plus media-protected sources. Explicit return selects the source tab, window and exact peek. The return target is transient and clears on normal tab selection or peek changes. Promotion is hidden for a returned non-topmost peek.
- `astra/Models/Core/Browser.swift`, `astra/Models/Tabs/BrowserTab.swift`, `astra/UI/Shell/BrowserWindowController.swift`, and `astra/UI/Shell/MiniAstraWindowController.swift` guard tab, peek, window, mini-window and quit teardown. iOS tab/peek closure uses its existing native confirmation UI.
- `checks/picture-in-picture-check.mjs`, `docs/astra-roadmap/checks-24a-picture-in-picture.swift`, and `docs/astra-roadmap/fixtures/picture-in-picture/` contain production-script checks, protection checks and inline, iframe, multiple-video and ineligible-media fixtures.

Acceptance cases and evidence:

- The public WebKit configuration property says HTML5 video PiP is enabled by default. Astra explicitly enables it where the SDK exposes the setting on iOS. This establishes API availability, not device behavior. [Apple `allowsPictureInPictureMediaPlayback`](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/allowspictureinpicturemediaplayback)
- The action checks playable video dimensions/readiness, `disablePictureInPicture`, and the WebKit per-video presentation-mode support before enabling browser controls. It uses `requestPictureInPicture()` where the standard API is available, or WebKit's documented `webkitSupportsPresentationMode` / `webkitSetPresentationMode` path. A rejected browser command is disabled for that document and leaves the website's own player controls available. [Apple WebKit PiP media-controls guidance](https://developer.apple.com/documentation/webkitjs/adding_picture_in_picture_to_your_safari_media_controls)
- `closeAllMediaPresentations` coordinates native PiP/fullscreen shutdown when navigation or confirmed teardown occurs. [Apple `closeAllMediaPresentations`](https://developer.apple.com/documentation/webkit/wkwebview/closeallmediapresentations%28completionhandler%3A%29)
- Hibernation, close, return-to-source, tab/window switching, backgrounding, process termination, and real PiP entry/exit have not been exercised in Astra. The fixture files describe cases; they were not launched.

Checks run:

- `bun run checks/picture-in-picture-check.mjs` — passed against the actual injected eligibility, polling and async action scripts. Cases cover missing APIs, standard success/rejection, WebKit-only support and exit, unsupported presentation, missing setter, zero dimensions, readiness, ended/disabled video and multiple players.
- `swiftc -o /tmp/astra-pip-policy-check astra/Web/Navigation/BrowserPictureInPicturePolicy.swift docs/astra-roadmap/checks-24a-picture-in-picture.swift && /tmp/astra-pip-policy-check` — passed.
- `git diff --check` — passed.
- Cumulative prerequisite check: the packet 14 production-helper check passed in this worktree with output `address/search checks passed`; the exact command and covered cases are recorded in [the packet 14 handoff](14-address-search-config.md).
- Xcode MCP workspace `workspace-hbZHh2ZjSU`, scheme `astra`, destination `My Mac`: the initial builds identified and resolved a Swift argument-order error and an isolated-world polling callback overload issue. The final Mac build passed in 8.871 seconds with no errors; Xcode reported zero issues in `BrowserController.swift`, `Browser.swift`, `BrowserTab.swift`, `BrowserContentView.swift`, and `PeekStackView.swift`. No iOS build or runtime test was performed.

Checks written but not executed: the HTML fixtures require a real WebKit window/device and user interaction. Hosted tests were not run.

Pending runtime/provider cases: validate actual user-initiated entry and native controls on macOS and iOS; page-evaluated commands may fail WebKit's user-activation or provider checks. Validate active/paused state, native exit, exact source focus, retained playback while switching tabs/spaces/windows/fullscreen and backgrounding, private sessions, multiple videos/windows, iframe PiP, DRM/provider restrictions, navigation and close prompts, mini-window promotion, quit, and process termination. iOS scene/audio-background behavior remains packet 32's gate. No runtime or provider acceptance is claimed.

Migration, compatibility and private-data impact: no persistence, sync, schema, dependency, or entitlement changes. PiP flags, return-target controller identity and failed-command state are transient. Private-window data remains in its existing isolated session.

Capability gates / unresolved issues: native video PiP support is WebKit/provider dependent. Browser eligibility and state observation are main-frame only. An iframe's native PiP cannot be reported precisely; playing or paused media is conservatively retained and protected. `WKWebView` exposes no callback that distinguishes the PiP system's return-to-app action from ordinary PiP dismissal, so users can explicitly invoke “Show Picture in Picture Tab” while the browser tracks an active source; automatic return-button focus remains unverified. PiP in peeks can move between the peek presentation and retained WebKit stack on tab switches; native continuity needs runtime verification.

Merge prerequisites / follow-up ownership: primary review and corrected Xcode MCP build. Preserve the listed iframe, automatic system-return, background, provider and view-detachment gates. No push or original-checkout integration occurred.
