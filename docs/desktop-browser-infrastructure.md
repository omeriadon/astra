# Astra desktop browser infrastructure

Research date: 30 September 2026. Scope: macOS desktop shell, shared browser services, and website compatibility. Mobile is excluded.

The research body records the pre-implementation assessment. The implementation ledger at the end records the subsequent work. This is a source-based assessment and implementation backlog. The recent desktop implementation builds, but its website behavior and hardware integration have not been exercised. “Implemented” below means code exists, not that the feature has passed compatibility testing. No app was launched during this research.

The assessment uses Apple's current documentation, WebKit's official publications and source, web standards, and Astra's current source. The installed SDK is Xcode 27.2 beta 1; the app currently targets macOS 27. WebKit upstream `main` is evidence about implementation boundaries, not proof that a particular change ships in the installed framework. Safari product features are not automatically available to an application embedding `WKWebView`.

## What the architecture must preserve

Normal windows and all spaces share website storage, cookies, logins, and site permission decisions. Spaces organize tabs; they are not browser profiles. Each private window currently has its own temporary session, flat tab sidebar, and download list. Private tabs, permissions, favicon history, and download records must not enter normal persistence, sync, extensions, or another private window. Completed downloaded files remain on disk by design.

Reuse `BrowserWebSession` as the ownership boundary for website data, permission decisions, downloads, and favicon caches. Keep navigation and the lifetime of an individual web view with `BrowserController`. Keep the desktop shell responsible for presenting controls and prompts. No new browser engine, generic service framework, custom cache, or custom audio mixer is justified by this report alone.

WebKit already provides the rendering engine, JavaScript runtime, network loading, standard website storage, and substantial media support. Astra owns browser policy, native integration, safe lifecycle management, and verification. The public embedding API also imposes limits. [Apple: WKWebView](https://developer.apple.com/documentation/webkit/wkwebview), [Apple: website data stores](https://developer.apple.com/documentation/webkit/wkwebsitedatastore).

Priorities:

- **P0:** Resolve before trusting Astra with ordinary daily browsing. Includes data-loss prevention, security boundaries, and feasibility decisions for explicitly required features.
- **P1:** Complete the everyday desktop browser baseline.
- **P2:** Mature-browser features, optional integrations, or work required only by a defined product commitment.
- **Engine:** WebKit/OS owns the mechanism. Astra must preserve it and test it rather than recreate it.
- **Gate:** Public API support or third-party acceptance remains unresolved. Do not label the feature supported until the gate passes.

## Spatial audio: explicit requirement, separate acceptance gate

“Spatial audio” refers to several different mechanisms. They need separate checks.

| Mechanism | Owner and evidence | Astra requirement |
| --- | --- | --- |
| Website positional audio | Web Audio's `PannerNode` and `AudioListener` place audio in space; HRTF is a spatialization model in the standard. | Preserve the website's audio graph. Verify positional audio and AudioWorklet playback. Do not apply a second browser-owned spatializer. [Web Audio standard](https://www.w3.org/TR/webaudio/). |
| Multichannel media and Dolby Atmos | Media decoding, container/codec support, output route, and content delivery determine the result. Spatialized stereo is not proof of Atmos decoding. | Test known multichannel and Atmos reference content through Astra, including its original channel metadata. A “spatial” badge must distinguish verified output from a stereo effect. |
| AirPods fixed spatial audio | macOS exposes spatial controls for supported apps and content on supported hardware. | Verify Astra appears as a supported playing app in the system controls. Respect the user's Off/Fixed choice. [Apple's spatial audio controls](https://support.apple.com/en-au/guide/airpods/dev00eb7e0a3/web). |
| AirPods head tracking | Depends on app/content support, Apple silicon, supported headphones, and system settings. | Test Head Tracked mode, movement, foreground/background transitions, fullscreen, and multiple windows. Ordinary stereo playback does not establish head-tracking support. [Apple's hardware and app conditions](https://support.apple.com/en-au/guide/airpods/dev00eb7e0a3/web). |
| Custom native-player spatial settings | The researched `AVPlayer.intendedSpatialAudioExperience` API is unavailable on macOS in the installed SDK; its current documented platform availability is visionOS. An app-owned player also does not control WebKit's internal players. | Do not add an `AVAudioSession` or native-player property as a pretend fix for desktop web audio. [Apple API](https://developer.apple.com/documentation/avfoundation/avplayer/intendedspatialaudioexperience-1bd87). |

There is no public spatial-audio switch in the installed `WKWebView`, `WKWebViewConfiguration`, or `WKPreferences` headers. That is an API observation, not proof that every spatial output path is unavailable. WebKit's AVFoundation backend has platform-conditioned spatial handling; the examined spatial tracking helper is gated to visionOS in upstream platform definitions. It cannot establish macOS support merely because it exists in WebKit source. [WebKit media backend](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/graphics/avfoundation/objc/MediaPlayerPrivateAVFoundationObjC.mm), [WebKit platform definitions](https://github.com/WebKit/WebKit/blob/main/Source/WTF/wtf/PlatformHave.h).

**SPATIAL-01, P0 feasibility / P1 acceptance:** Keep spatial audio on the required compatibility list. Use supported Apple silicon and AirPods, known reference media, and a Safari comparison on the same machine. Record Astra's actual fixed, head-tracked, multichannel, and Web Audio outcomes separately. If a required path cannot work through public WebKit embedding APIs, record an engine/API limitation and investigate that specific path. There is currently no verified implementation to claim as complete.

The existing sidebar card reports media playback and offers pause; it does not detect spatial output, decode Atmos, expose precise audible state, or provide a complete media session UI. [Current card](../astra/UI/Chrome/BrowserMediaActivityView.swift), [current media observation](../astra/Web/Navigation/BrowserController.swift).

## Highest-priority findings in the current implementation

| Finding | Evidence in Astra | Required next work |
| --- | --- | --- |
| Screen-only sharing is not included in hibernation protection. | `canHibernate` checks playback, camera, microphone, dirty input, and loading. No screen/window/system-audio capture state is checked. | **P0:** Prove reliable protection for screen-only WebRTC sessions. Until that exists, automatic destructive hibernation needs a conservative policy. The camera/microphone guards are insufficient for a screen-sharing claim. [Controller](../astra/Web/Navigation/BrowserController.swift), [memory-pressure handling](../astra/App/AppDelegate.swift). |
| Relaunch restoration is substantially weaker than in-process hibernation restoration. | `storedInteractionState` is memory-only. `OpenTab` persists URLs, URL history, zoom, scroll, and peeks. | **P0:** Define exactly what is restored after a crash or restart. Verify native back/forward behavior, sessionStorage, and recoverable drafts without persisting passwords or private data. [Tab](../astra/Models/Tabs/BrowserTab.swift), [persisted tab](../astra/Models/Tabs/OpenTab.swift). |
| Persistence is atomic per file, not across the whole browser snapshot. | `savePersistedState` writes multiple independent JSON files. Writes are now serialized, but interruption between files can leave mixed generations. | **P0:** Make recovery identify a coherent generation and retain the last valid snapshot. Test interruption and corrupt input. A single snapshot or a small generation/manifest scheme is enough; a database is not automatically required. [Persistence](../astra/Storage/BrowserPersistence.swift). |
| Unsaved-work detection is a heuristic. | A trusted-input listener sets a dirty flag; a main-frame submit clears it. Apps may save asynchronously, use custom editors, or perform programmatic state changes. | **P0:** Treat the dirty flag as conservative protection, not proof of saved state. Validate native beforeunload decisions and avoid destructive suspension when work cannot be classified safely. [Controller](../astra/Web/Navigation/BrowserController.swift), [website dialogs](../astra/Web/Navigation/BrowserWebsiteUI.swift). |
| Browser download quarantine is not established by the current source/configuration. | No explicit quarantine policy was found. The inspected Info.plist and evaluated build settings do not declare `LSFileQuarantineEnabled`. Segmented downloads recreate files using app-owned I/O. | **P0:** Verify quarantine and origin metadata on normal, resumed, segmented, renamed, and private downloads. Do not assume native download metadata survives a custom acceleration path. [Download manager](../astra/Web/Downloads/BrowserDownloadManager.swift). |
| Ordinary HTTP compatibility lacks a deliberate transport policy. | The inspected source and evaluated settings contain no web-content ATS exception. HTTPS-only fallback preferences are not configured. | **P0:** Decide and test browser handling of public HTTP, local development servers, HTTPS upgrades, and failed upgrades. Keep app-owned sync/update traffic secure. |
| OS authentication-session handling is missing. | The app registers HTTP/HTTPS URLs, but no `ASWebAuthenticationSession` browser-handler capability or session manager implementation was found. | **P1:** Support other apps' authentication sessions, callbacks, cancellation, and ephemeral requests. Default-browser registration alone is not sufficient. |
| Web Push hosting is absent. | No public hosting API was found in the installed SDK; upstream push dispatch and notification interaction APIs examined are private. | **P0 gate:** Resolve a supported hosting/engine strategy. Local native notifications are not website Web Push. |
| Private isolation has code, not behavioral proof. | Temporary stores, disabled extensions/sync, isolated downloads/favicons, and close cleanup exist. | **P0:** Verify no private artifacts reach app storage, sync payloads, extension windows, search suggestions, or normal tabs. Test abnormal termination as well as orderly close. |
| A media-playing state is not the same as an audible state. | The sidebar polls `requestMediaPlaybackState`. | **P1:** Cover muted video, Web Audio, cross-origin players, calls, and multiple simultaneous players. Do not infer audible output or a working mute control from playback state. |
| Prompt concurrency currently has a cancellation shortcut. | Native website prompts return a negative/cancel result if a sheet is already attached. | **P1:** Define per-window prompt ordering, background-tab attribution, and cancellation on navigation/close. Keep accidental dismissal separate from a persisted permission refusal. |
| Engine-specific integration uses private selectors. | Web Inspector setup and titlebar integration use private KVC/selectors. | **P1:** Inventory and contain these dependencies, test each supported OS, and keep graceful fallbacks. Avoid growing the dependency into essential security or storage behavior. |

These findings are architectural and verification gaps. This report does not assert that each gap has already caused a user-visible failure.

## Complete infrastructure map

### Engine, network, and security

| ID | Infrastructure | Current ownership/status | Required work and acceptance |
| --- | --- | --- | --- |
| E01 | HTML, CSS, JavaScript, DOM, layout, fonts, rendering | **Engine.** Supplied by system WebKit. | Maintain an OS compatibility matrix. Test selected standards and real websites; do not build a rendering engine. |
| E02 | Process separation, renderer/GPU/network sandbox | **Engine + P0 verification.** App Sandbox and Hardened Runtime are enabled. | Preserve WebKit's boundaries and narrow host entitlements. Test renderer termination and host responsiveness. Do not claim Chromium-style site isolation from separate tab objects. |
| E03 | HTTP versions, redirects, DNS, TLS, connection pooling | **Engine.** Website requests use WebKit; sync and auxiliary fetches use URLSession. | Test VPNs, system proxies, captive portals, network changes, offline transitions, and local servers. Keep these network stacks' caches and cookies conceptually separate. |
| E04 | HTTP compatibility and HTTPS-first policy | **P0.** No explicit broad web-content transport policy found. | Permit intended browser use without disabling secure app-owned requests. Show HTTP/insecure status and define user-mediated fallback. |
| E05 | Certificate trust, expiry, hostname failures, mixed content | **Engine + P0/P1 UI.** Default challenge handling and secure-connection errors exist. | Retain trust validation. Show committed origin and connection state. Test expired, self-signed, wrong-host, and mixed-content cases; no automatic trust bypass. |
| E06 | Phishing and malware warnings | **Engine + P0 verification.** Public preference defaults to enabled. | Confirm it remains enabled and is not hidden by Astra's error/chrome layers. Keep any provider/privacy dependencies documented. |
| E07 | Origin display, IDN, spoof-resistant chrome | **P0.** URL display styling exists, but no documented anti-spoof validation. | Test Unicode domains, credentials in URLs, redirects, long hosts, escaped characters, and page attempts to imitate browser chrome. Use the committed URL for trusted UI. |
| E08 | Same-origin policy, CSP, CORS, iframe permissions, secure contexts | **Engine.** | Never work around website failures by disabling these protections. Test Astra's injected scripts and native bridge against hostile frames. |
| E09 | Native script-message bridge security | **P0.** Several message handlers and isolated content worlds exist. | Validate frame, origin, expected payload shape, and navigation lifetime for privileged operations. Keep untrusted page messages unable to grant access, write files, or change browser settings. |
| E10 | System proxies / optional per-session proxies | **Engine + P2 UI.** Public data-store proxy configuration exists; no custom UI found. | Honor system behavior first. If adding overrides, define normal/private scope and connection replacement; avoid a bespoke proxy or DNS implementation. |
| E11 | Tracking prevention and cross-site cookie compatibility | **Engine + P1 testing.** ITP is enabled by default in WKWebView. | Test embedded login, third-party payments, and Storage Access flows. Diagnose before adding any narrowly scoped exception; do not globally disable privacy controls to fix one site. |
| E12 | Global Privacy Control / privacy preferences | **P1 product policy.** No GPC setting found. | Use the public per-page API available in the current SDK, and communicate the chosen behavior. Do not confuse GPC with technical tracker blocking. |

Apple provides a web-content-only ATS exception and a public HTTPS navigation policy; the exception does not turn an HTTP page into a secure context. Certificate validation remains a separate concern. [Web-content ATS key](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsinwebcontent), [HTTPS navigation policy](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/upgradetohttpspolicy), [server trust](https://developer.apple.com/documentation/webkit/wkwebview/servertrust).

Fraud-warning defaults and ITP are documented engine behavior, not new Astra services. [Fraudulent website warnings](https://developer.apple.com/documentation/webkit/wkpreferences/isfraudulentwebsitewarningenabled), [WebKit ITP in WKWebView](https://webkit.org/blog/10882/app-bound-domains/), [Storage Access API](https://webkit.org/blog/11545/updates-to-the-storage-access-api/). Per-session proxy configuration is public. [Proxy API](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/proxyconfigurations-6g21z).

The September 2026 WebKit release documents public GPC, form-submission, navigation-correlation, and content-world additions. Use their specific SDK availability instead of extrapolating from Safari's product UI. [WebKit 27 embedding additions](https://webkit.org/blog/18325/webkit-features-for-safari-27-0/).

### Storage, sessions, privacy, and offline behavior

| ID | Infrastructure | Current ownership/status | Required work and acceptance |
| --- | --- | --- | --- |
| S01 | Shared normal cookies and website storage | **Implemented + P0 testing.** Shared default website data store. | Log into a site in one space/window; confirm expected access in another. Explicitly preserve spaces as tab organization. |
| S02 | Private sessions | **Implemented + P0 testing.** Nonpersistent store per private window. | Normal-to-private, private-to-normal, and private-window-to-private-window isolation; close/reopen; renderer crash; force quit; no private persistence or sync. |
| S03 | Cookie semantics and partitioning | **Engine + P1 testing.** | Cover HttpOnly, Secure, SameSite, expiration, third-party storage, embedded providers, and localhost development. Do not duplicate browser cookie rules in Swift. |
| S04 | HTTP memory/disk cache | **Engine + P1 testing.** Default request policies are retained. | Cover freshness, validators, 304 responses, Vary, no-store, reload, force reload, private cache lifetime, and offline cache misses. |
| S05 | Website-managed offline support | **Gate + P1.** Service-worker availability has not been tested in Astra. | Test HTTPS service-worker registration, interception, Cache Storage, IndexedDB, reload offline, update/unregister, and data clearing. Do not infer support from Safari or from the existence of a data-type constant. |
| S06 | Quota, persistence requests, and eviction | **Engine + P1 testing.** | Verify actual origin limits and persistent-storage behavior. Explain that best-effort site storage can be evicted. Browser classification can affect quotas. |
| S07 | Data clearing | **Implemented + P1 completion.** All-site, per-site, cache, favicon, and permission controls exist. | Verify removal of every intended data type, logout behavior, active pages, and private scope. Define separately whether clearing cookies also resets permissions. |
| S08 | History deletion and retention | **P1.** Open/closed tab URL records exist; website-data clearing does not erase browser history. | Add explicit history controls, retention policy, individual deletion, and a clear distinction between navigation state, closed tabs, and history records. |
| S09 | Coherent local browser snapshots | **P0.** JSON files are written independently. | Recover one coherent snapshot after interruption, validate input, handle schema versions, retain a last-good copy, and report save failures. |
| S10 | Session recovery after relaunch/crash | **P0/P1.** URLs and some view state are persisted; native interaction state is memory-only. | Distinguish in-process wake, ordinary relaunch, and crash recovery. Verify back/forward entries, sessionStorage, draft policy, and lazy restoration. |
| S11 | Tab suspension and discard policy | **Implemented partly + P0.** Memory-pressure discard and activity guards exist. | Protect calls, screen sharing, unsaved work, downloads, PiP, and user-interactive background activity. Prefer WebKit's idle scheduling until destructive discard is proven safe. |
| S12 | Saved pages for deliberate offline reading | **P1 if included in baseline.** No save/reopen workflow found. | Offer a web archive or PDF with a clear scope. Cached resources are not a complete saved page, and an archive is not an offline replica of an arbitrary web application. |

WebKit distinguishes website storage quotas from cookies and HTTP cache, uses eviction policies, and supports Storage API persistence requests. Its published policy also distinguishes browser and other-app quotas; the actual classification and runtime behavior need testing in Astra. [WebKit storage policy](https://webkit.org/blog/14403/updates-to-storage-policy/).

Service-worker support has historically had embedding restrictions. An old report cannot prove present macOS behavior, and iOS App-Bound Domains guidance must not be treated as a desktop configuration recipe. This remains a runtime gate, not a reason to restrict a general browser to ten domains. [WebKit's service-worker support correction](https://webkit.org/blog/8090/workers-at-your-service/), [App-Bound Domains scope](https://webkit.org/blog/10882/app-bound-domains/).

`interactionState` is an opaque native interaction-state object; it is not interchangeable with a list of URLs. The current public fetch/restore API's available `WKWebViewDataType` in the installed SDK is sessionStorage, not an all-purpose browser-session serializer. [Interaction state](https://developer.apple.com/documentation/webkit/wkwebview/interactionstate), [data restoration](https://developer.apple.com/documentation/webkit/wkwebview/restoredata(_:completionhandler:)).

Native idle scheduling already exempts media/capture and other user-interactive activity; destructive app-owned hibernation needs equivalent protection. [Inactive scheduling policy](https://developer.apple.com/documentation/webkit/wkpreferences/inactiveschedulingpolicy-swift.property).

### Navigation, windows, forms, and everyday interactions

| ID | Infrastructure | Current ownership/status | Required work and acceptance |
| --- | --- | --- | --- |
| N01 | Live back/forward and same-document history | **Implemented + P0 testing.** Native navigation is now used. | POST navigation, resubmission decisions, redirects, fragments, pushState/replaceState, back-forward cache, duplicate URLs, and failed navigation. |
| N02 | New tabs, popups, and opener relationships | **Implemented partly + P0/P1.** WebKit's supplied configuration is used; peeks are preserved. | Test window.open, about:blank then document.write, named targets, postMessage, opener, noopener, COOP, window.close, and login/payment popups. Audit the replacement user-content controller for inherited behavior. |
| N03 | Link gestures and background opening | **P1.** Shift-click routing exists; full desktop gesture coverage is not established. | Command-click, middle-click, Shift-click, context-menu opening, foreground/background selection, drag-to-open, and accessibility actions. Preserve requests where appropriate. |
| N04 | Address interpretation and search | **Implemented partly + P1.** URL/search handling and Google suggestions exist. | IPv6, localhost ports, Unicode, escaped URLs, malformed input, custom schemes, search-provider settings, and cancellation of stale suggestions. |
| N05 | Reload, force reload, stop, network errors | **Implemented + P1 testing.** | Differentiate network, certificate, renderer, and cancellation failures. Preserve typed address and retry context. Avoid automatic replay of state-changing submissions. |
| N06 | JavaScript dialogs and beforeunload | **Implemented + P0/P1.** Native alert/confirm/prompt and beforeunload hooks exist. | Prompt ordering, attribution, background tabs, iframe origins, navigation/close cancellation, and abuse suppression. Test editor state beyond ordinary input fields. |
| N07 | File upload and directory selection | **Implemented + P1 testing.** Native open panels exist. | Single/multiple files, directory upload, cancellation, sandbox grants, drag-and-drop uploads, file-input accept filters, and camera-related site flows where applicable. |
| N08 | Context menus, copy/paste, drag-and-drop | **Engine + P1 shell completion.** | Open/copy/save links and images, selected text, clipboard restrictions, files, rich text, keyboard context menus, and conflicts with shell gestures. |
| N09 | Find in page | **P1.** No dedicated app workflow found. | Command-F, next/previous, wrap, case handling, selection, Escape, iframe/PDF behavior, and focus return. Use native find facilities. |
| N10 | Printing, PDF export, archive export | **P1.** No app workflow found. | Command-P, print dialog, print backgrounds, page sizing, PDF save, cancellation, sandbox destinations, and reading the saved output. |
| N11 | Fullscreen, pointer lock, focus, Escape | **Engine + P1 testing.** Element fullscreen is enabled. | Browser chrome remains trustworthy; restore controls/focus after exit; keyboard games and embedded players work; Escape is not incorrectly consumed by peeks. |
| N12 | Unsaved work and window/tab closure | **Implemented partly + P0.** App close prompts use a dirty heuristic. | Native beforeunload, unsaved drafts, nested peeks, bulk closes, close-window, quit, renderer death, and memory discard need consistent policies. |

The HTML standard defines navigation/history and user activation; rebuilding requests from URLs can lose behavior those mechanisms preserve. [Navigation and history](https://html.spec.whatwg.org/multipage/nav-history-apis.html), [user activation](https://html.spec.whatwg.org/dev/interaction.html).

Native APIs exist for find, web archive, PDF generation, and macOS printing. Astra needs the commands and workflows, not separate search/rendering engines. [Find API](https://developer.apple.com/documentation/webkit/wkwebview/find(_:configuration:completionhandler:)), [archive and related export APIs](https://developer.apple.com/documentation/webkit/wkwebview/createwebarchivedata(completionhandler:)).

### Permissions, identity, payments, and OS authentication

| ID | Infrastructure | Current ownership/status | Required work and acceptance |
| --- | --- | --- | --- |
| A01 | Camera, microphone, location | **Implemented + P0 testing.** Per requesting-origin and top-origin decisions; native resource access configuration. | Website grant/refusal, system refusal, later system revocation, embedded-origin attribution, private sessions, device switching, and visible active-capture state. |
| A02 | Permission management and revocation semantics | **Implemented partly + P1.** Reset controls exist; camera/microphone capture can stop. | Define Allow/Block/Ask, temporary grants, reset versus revoke, location-watch lifetime, and active-session behavior. Resetting future decisions is not proof that an existing location watch stopped. |
| A03 | Screen/window/system-audio capture | **Gate + P0.** No app-level management or hibernation guard found. | Verify getDisplayMedia, native picker/TCC, cancellation, sharing indicators, stop, and background protection. Browser screen-sharing permissions must not be modeled as camera permission. |
| A04 | Clipboard, local-network, storage-access, and other web capabilities | **Engine/API-dependent + P1.** No unified app-level coverage established. | Inventory which prompts WebKit/OS handles and which hooks are public on macOS. Preserve activation/secure-context rules and test denied requests. Do not expose capabilities through a privileged JS workaround. |
| A05 | Passkeys and physical security keys | **Engine + P1 validation.** No separate browser credential-access workflow found. | Test creation, sign-in, conditional UI where supported, cancellation, browser authorization, third-party credential providers, and hardware keys. Use Apple's browser APIs only where required. |
| A06 | Password AutoFill, generated passwords, one-time codes | **Engine/platform + P1 validation.** General password-manager functionality is not established. | Check actual macOS WKWebView behavior before writing a manager. Validate provider UI, field recognition, iframe security, and saving/updating credentials. Astra's sync-token Keychain item is not a website password store. |
| A07 | HTTP authentication, proxy authentication, client certificates | **Implemented partly + P1.** Basic/digest/default website prompts exist; other methods use system handling. | Wrong credentials, retry limits, cancellation, credential lifetime, redirects, downloads, proxy challenges, client certificates, and certificate-store access. |
| A08 | Website OAuth/SSO flows | **P1 testing.** Popups and shared cookies have foundations. | Provider login redirects, cookie restrictions, postMessage, callback schemes, popup close, and private sessions. Some providers may reject embedded user agents; user-agent spoofing is not a reliable fix. |
| A09 | Other apps' ASWebAuthenticationSession requests | **P1 missing.** | Register and implement macOS session handling, callback matching, cancellation, and ephemeral-session support. Preserve browser-to-requesting-app isolation. |
| A10 | Apple Pay / Payment Request / payment popups | **Gate + P1.** No verified desktop compatibility. | Test current macOS support, script-injection interaction, current merchant integrations, and third-party browser routes. Do not add merchant credentials to a general browser to pretend it is every merchant. |

Apple documents automatic handling of WebAuthentication challenges in WKWebView and browser-specific credential authorization. This supports a native-first verification plan, not a blanket claim that every password/AutoFill feature works automatically on desktop. [Passkeys in browsers](https://developer.apple.com/documentation/authenticationservices/passkey-use-in-web-browsers), [password use in browsers](https://developer.apple.com/documentation/authenticationservices/password-use-in-web-browsers).

macOS browsers must explicitly participate in authentication-session handling; otherwise the system can fall back to Safari. This is separate from Astra's own Sign in with Apple. [Browser SSO integration](https://developer.apple.com/documentation/authenticationservices/supporting-single-sign-on-in-a-web-browser-app).

Screen capture is a distinct permission model. A historical WKWebView camera/microphone-delegate interaction bug was fixed; its existence is a regression-test reason, not proof that current screen sharing is unsupported. [Screen capture standard](https://www.w3.org/TR/mediacapture-screen-share/), [WebKit capture regression](https://bugs.webkit.org/show_bug.cgi?id=274896).

A WebKit issue reports macOS WKWebView Apple Pay limitations; treat it as a compatibility risk requiring current tests, not definitive evidence for every present macOS version. Merchants also have Apple-supported third-party browser payment routes. [WebKit issue](https://bugs.webkit.org/show_bug.cgi?id=282078), [Apple Pay third-party browser guidance](https://applepaypartners.apple.com/merchants/features/apple-pay-in-third-party-browsers).

### Media, sound, streaming, and notifications

| ID | Infrastructure | Current ownership/status | Required work and acceptance |
| --- | --- | --- | --- |
| M01 | HTML audio/video, Web Audio, AudioWorklet | **Engine + P1 testing.** Native page playback is retained. | Audio-only pages, cross-origin players, games, suspended/resumed contexts, decoding failures, and multiple tabs. |
| M02 | Spatial audio | **Required gate.** See SPATIAL-01. | Independently validate Web Audio positioning, multichannel/Atmos, fixed spatial audio, and AirPods head tracking. |
| M03 | Autoplay and per-site playback policy | **Implemented partly + P1.** Audio requires user action. | Silent video, audible playback after activation, embeds, subsequent navigations, and site exceptions where a supported implementation is available. |
| M04 | Accurate sound indicators and tab mute | **P1 / API gate.** Playback card and pause exist. | Distinguish audio from muted video; preserve pause versus mute semantics. The examined native page-mute/audible helpers are private. A DOM-only implementation would need explicit limits for cross-origin frames and Web Audio. |
| M05 | Media Session and system Now Playing | **P1 / API gate.** No dedicated app-owned Now Playing integration found. | Metadata/artwork, play/pause/seek, headset/media keys, active-player arbitration, and correct cleanup. Verify what WebKit supplies before duplicating it. |
| M06 | Picture-in-Picture and fullscreen video | **Engine + P1 testing.** Fullscreen is enabled; desktop PiP behavior is unverified. | Enter/exit/restore, tab/window close, background playback, multiple windows, and hibernation protection. Do not apply iOS-only configuration APIs to macOS. |
| M07 | AirPlay and output-route changes | **Engine + P1 testing.** Public AirPlay preference defaults to allowed. | Native website route controls, connection/disconnection, device switching, headphones, HDMI, and continued playback. A separate native AVPlayer is not the website's player. |
| M08 | Captions, alternate tracks, playback speed, accessibility | **Engine + P1 testing.** | Verify site/native player controls and system caption preferences; do not lose them behind overlays or custom player replacements. |
| M09 | HLS, MSE, WebCodecs, codecs, HDR, GPU paths | **Engine + P1 matrix.** | Test supported streams and fallback behavior on the supported Mac/OS range. Hardware and provider policies matter; an API name does not establish a usable codec path. |
| M10 | DRM and commercial streaming acceptance | **Gate + P1.** No provider compatibility proof. | Test providers and license/key-system behavior individually. FairPlay and Widevine are not interchangeable; changing UA strings does not supply DRM or certification. |
| M11 | WebRTC calls and networking | **Engine + P0/P1 testing.** Camera/microphone foundation exists. | Background calls, reconnect, screen sharing, device changes, mute/unmute, permission changes, and network transitions. Sites own their signaling and TURN services; Astra does not need a universal calling backend. |
| M12 | Website Notifications API | **Gate.** Not implemented. | Origin-bound requests, permission lifetime, OS authorization, tags/replacement, close events, click routing, and abuse controls. No placeholder claim of support. |
| M13 | Website Web Push and background delivery | **Required P0 gate.** No supported hosting route established. | Standards-compliant subscriptions, encrypted payloads, site workers, OS wake/delivery, closed-tab behavior, browser restart, click routing, expiration, unsubscribe, and site-data removal. |

WebKit's public playback-state and pause facilities are broader than an audible-state API. Upstream's explicit audible-state and page-mute interfaces are in `WKWebViewPrivate.h`. This is why the present activity card is only a foundation. [Public playback-state API](https://developer.apple.com/documentation/webkit/wkwebview/requestmediaplaybackstate(completionhandler:)), [private interface boundary](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h).

System media integration should respect website Media Session semantics and arbitrate competing sessions. [Media Session specification](https://www.w3.org/TR/mediasession/). AirPlay is already allowed by the public configuration's documented default; the next work is compatibility verification, not adding a redundant toggle. [AirPlay configuration](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/allowsairplayformediaplayback).

Commercial streaming has content-protection requirements beyond HTML playback. This is a provider/engine compatibility task, not justification for intercepting or decrypting protected streams. [FairPlay Streaming](https://developer.apple.com/streaming/fps/).

**Web Push is an architectural gate.** Safari's support includes OS integration and worker dispatch. The examined upstream dispatch/click/close interfaces are private, and the installed public headers contain no corresponding host integration. Native `UNUserNotificationCenter` messages cannot provide arbitrary websites with interoperable Push API subscriptions. Declarative Web Push does not itself grant an embedded browser those hosting APIs. [Safari Web Push architecture](https://webkit.org/blog/12945/meet-web-push/), [Declarative Web Push](https://webkit.org/blog/16535/meet-declarative-web-push/), [private data-store interfaces](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStorePrivate.h).

### Downloads, local files, and documents

| ID | Infrastructure | Current ownership/status | Required work and acceptance |
| --- | --- | --- | --- |
| D01 | Downloads and navigation handoff | **Implemented + P1 testing.** WKDownload, content-disposition/MIME decisions, and page restoration exist. | Link downloads, blobs, data URLs, forms, frames, new-window downloads, cookies, authorization, redirects, and cancellation. |
| D02 | Resume and acceleration correctness | **Implemented + P0/P1 testing.** Resume data and validated range segments exist. | Changed resources, weak/strong validators, compressed responses, server range refusal, interrupted writes, disk-full, and fallback. Preserve authentication and privacy on every path. |
| D03 | Safe names and file destinations | **Implemented partly + P0/P1.** Name sanitization and collision handling exist. | Dangerous extensions, Unicode names, deceptive double extensions, case-insensitive collisions, symlinks, directory changes, and destination access. |
| D04 | Quarantine and download origin metadata | **P0 missing proof.** | Verify actual attributes on every download path and after rename/move. Use system facilities to preserve the browser-origin security boundary. |
| D05 | Persistent user-selected locations | **P1 when adding Save As / custom download directories.** Downloads-folder access exists. | Security-scoped bookmarks, stale bookmarks, revoked grants, cancellation, moved files, and relaunch access. |
| D06 | Private downloads | **Implemented + P0 testing.** Private history is temporary and acceleration is disabled. | Ensure normal manager/sync/logs do not record private origins. Define window-close cancellation, keep completed files, and remove incomplete temporary files reliably. |
| D07 | Open local HTML, images, PDF, and archives | **Engine + P1 workflow.** No complete Open File/export reopening workflow established. | Narrow file read-access scope, local-resource handling, file:// origin behavior, sandbox permissions, and external links from local content. |
| D08 | PDF viewing, forms, print, and save | **Engine + P1 testing.** | Embedded/top-level PDF, find, fillable forms, links, download versus display, print/export, and accessibility. |

WKDownload has its own authentication and redirect delegate hooks; website navigation prompts alone do not complete download authentication handling. [WKDownloadDelegate](https://developer.apple.com/documentation/webkit/wkdownloaddelegate).

Apple documents `LSFileQuarantineEnabled`, including its disabled default, and security-scoped bookmarks for persistent sandbox access. Verify actual file attributes as well as configuration. [Quarantine configuration](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html), [sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

### Extensions and content protection

| ID | Infrastructure | Current ownership/status | Required work and acceptance |
| --- | --- | --- | --- |
| X01 | Extension runtime and host contract | **Implemented partly + P1.** WKWebExtensionController and tab/window bridges exist. | List supported APIs, validate common extensions, surface errors, and do not imply complete Chrome compatibility. |
| X02 | Permission and host-access model | **Implemented partly + P0 review.** Install prompts, site-access controls, file access, and runtime permission hooks exist. | Verify granted permissions match consent; cover optional permissions, changed manifests, update escalation, revocation, and activeTab lifetime. |
| X03 | Extension installation, identity, and updates | **Implemented partly + P1.** Bundled/imported/store installation paths exist. | Stable identity, package size limits, source provenance, manifest validation, safe update/rollback, and loss of external bundle access. |
| X04 | Private-window exclusion | **Implemented + P0 testing.** Private browser windows/views are excluded. | Verify tabs.query, windows APIs, background scripts, cookies, webRequest, downloads, and extension popups cannot see private session data. |
| X05 | Unsupported extension APIs | **P1.** No declared unsupported-API matrix found. | Use the host's unsupported-API facilities where appropriate; feature detection must fail clearly rather than expose a misleading API stub. |
| X06 | Ad/tracker rules and site exceptions | **Implemented partly + P1.** uBlock Origin Lite is bundled through extension integration. | Test actual blocking, rules updates, site exceptions, broken-site recovery, performance, and private policy. Reuse the existing mechanism before adding a second filter engine. |

WebKit exposes an `unsupportedAPIs` mechanism so extension authors can detect host limitations. Native content-rule lists also exist, but are not a reason to duplicate a working extension-based blocker. [Unsupported API declaration](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/unsupportedapis), [content rule lists](https://developer.apple.com/documentation/webkit/wkcontentruleliststore).

### Desktop integration, accessibility, sync, and distribution

| ID | Infrastructure | Current ownership/status | Required work and acceptance |
| --- | --- | --- | --- |
| O01 | Default-browser registration and external opening | **Implemented partly + P1 testing.** HTTP/HTTPS registration and default-browser settings exist. | Launch while closed/open, multiple incoming URLs, choosing the intended normal/private window, and system consent failures. |
| O02 | External application protocols | **Implemented + P1 testing.** Confirmation exists, with the mailto-copy preference preserved. | App availability, loops, repeated requests, navigation cancellation, callback URLs, and secure origin attribution. |
| O03 | macOS windows and first-responder chain | **Implemented + P1 testing.** Custom AppKit windows host SwiftUI/WebKit. | Native menus, keyboard shortcuts, minimization, fullscreen, multi-display resizing, focus, text editing, tab traversal, and closing behavior. |
| O04 | Accessibility of the browser and page boundary | **Implemented partly + P1 audit.** Labels/IDs and reduced-motion handling exist. | VoiceOver, keyboard-only use, focus after prompts/peeks, contrast, enlarged text, selected-tab announcements, and no overlays that block page controls. |
| O05 | Text input and language services | **Engine + P1 testing.** | IME/composition, dead keys, RTL, spellcheck, dictation, selection, rich-text editing, shortcuts, and system context menus. |
| O06 | Data import/export and migration | **P1.** No complete import/export workflow found. | Bookmarks and history first; clear treatment of password exports and sensitive files. Schema migration and export validation must preserve user data. |
| O07 | Sync identity, conflicts, deletion, and offline retry | **Implemented partly + P0/P1.** Sign in with Apple, Keychain token, HTTPS transport, snapshots, version checks, and merges exist. | Conflict/tombstone tests, expired sessions, retry/backoff, offline edits, clock skew, device removal, deletion behavior, and explicit private exclusion. |
| O08 | Sync confidentiality | **P1 explicit product policy.** Client encodes readable JSON payloads; no client-side encryption layer was found. | Do not describe transport encryption as end-to-end encryption. Decide the privacy promise before syncing passwords or other high-sensitivity data. Server security was not assessed here. |
| O09 | Secure updates and release packaging | **Implemented partly + P0/P1.** Sparkle integration and an EdDSA public key exist. | Test signed appcasts/archives, sandbox helper setup, failed updates, relaunch/session recovery, Developer ID distribution, notarization, and OS compatibility. |
| O10 | Engine security-update cadence | **Engine/OS + P0 release policy.** System WebKit controls engine updates. | State minimum supported OS and update expectations. Astra updates cannot necessarily patch an older OS's engine. An alternate bundled engine would add its own urgent patch pipeline. |
| O11 | Diagnostics, bug reports, and observability | **P1.** Error UI and inspector integration exist; no complete diagnostic policy found. | Capture build/OS/engine version and failure class. Redact URLs, tokens, forms, private origins, and content by default. Provide reproducible site failures without recording browsing history as telemetry. |
| O12 | Web developer tooling | **Implemented partly + P1.** Inspectability and an inspector menu exist, with private dependencies. | Verify inspect/console/network behavior, page source, developer preference scope, and normal/private policy. Safari tooling alone is not an automated Astra-shell test. |

macOS default-browser selection is a native system interaction, and browser authentication-session support has additional requirements. [Default application API](https://developer.apple.com/documentation/appkit/nsworkspace/setdefaultapplication(at:toopenurlswithscheme:completion:)), [authentication sessions](https://developer.apple.com/documentation/authenticationservices/supporting-single-sign-on-in-a-web-browser-app).

Browser accessibility includes both browser UI and the interface to assistive technology; website WCAG testing alone does not cover the browser shell. UAAG is useful browser-specific guidance, not a claim of certification. [W3C user-agent accessibility overview](https://www.w3.org/WAI/standards-guidelines/uaag/).

Safari's export facilities provide a practical interoperability target, but exported password data can be unencrypted. [Safari export behavior](https://support.apple.com/guide/safari/ibrwebf10132/mac). Sparkle's sandbox setup and Apple's notarization requirements need release-artifact validation, not just a Debug build. [Sparkle sandboxing](https://sparkle-project.org/documentation/sandboxing/), [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Inspectability is a supported public feature for embedded browsers. A deliberate browser preference is reasonable; enabling inspection is not inherently a defect. The separate private-selector dependencies still need containment. [WebKit inspection API](https://webkit.org/blog/13936/enabling-the-inspection-of-web-content-in-apps/).

## Compatibility ceilings and optional infrastructure

These are real considerations, but they do not all require an Astra-owned implementation.

| Area | Treatment |
| --- | --- |
| WebGPU, WebGL, Canvas, WebAssembly, codecs, web standards | Engine compatibility matrix. Test required applications. Do not create a separate implementation for missing engine features. |
| WebUSB, WebBluetooth, Web Serial, advanced filesystem APIs | Define intended browser scope and investigate actual engine support. A privileged native JS bridge is a separate security-sensitive product feature, not a routine compatibility patch. |
| Browser-installed PWAs / standalone site apps | P2 unless part of the stated baseline. Requires launch identity, windows, storage scope, update behavior, uninstall, and the same push/background gates. |
| Background Sync / periodic work | Verify engine support and lifecycle. Do not promise all Chrome background APIs just because service workers work. |
| Translation, reader mode, reading list | P2 product integrations. They need content handling and privacy decisions but are not prerequisites for basic page loading. |
| Separate accounts/profiles/containers | Not required by the current product definition. Spaces deliberately share identity. Introduce profiles only as an explicit additional feature. |
| Enterprise policy, managed configuration, proxy/PAC administration | P2 if targeting managed deployments. Otherwise preserve system networking and avoid a policy framework. |
| Native automation/MCP or a browser extension native-messaging bridge | P2 explicit product commitment. Requires separate authorization and isolation; never use automation access as a website security workaround. |
| Password-manager ownership / credential sync | Prefer native providers first. A new vault adds cryptography, recovery, breach handling, provider integration, and migration responsibilities. |
| Alternative browser engine | Feasibility study only if mandatory compatibility gates cannot be met. Chromium/CEF embedding adds process/helper packaging, sandboxing, platform integration, patch cadence, and engine-specific services. It does not automatically solve push, DRM, or Apple's spatial-audio integration. |

Chrome's process/site isolation is an engine-level architecture, not a switch Astra can recreate by adding another Swift service. A CEF path needs its own sandboxed subprocess integration. [Chromium site isolation](https://www.chromium.org/Home/chromium-security/site-isolation/), [CEF's macOS process helper](https://github.com/chromiumembedded/cef/blob/master/tests/cefsimple/process_helper_mac.cc).

## Verification infrastructure that is still required

Use three layers: small deterministic tests for Astra-owned decisions; local website fixtures for browser-host interactions; a documented real-site/hardware matrix. Adopt selected web-platform-tests rather than trying to rerun every engine test inside the app. WebKit/Safari conformance is useful evidence but does not cover Astra's delegates, private sessions, windows, or shutdown. [Web-platform-tests](https://web-platform-tests.org/).

The existing project instruction forbids launching/operating this app through computer-use tools. The following are acceptance cases for an appropriate test harness or manual execution; none is marked passed by this research.

| Test pack | Minimum acceptance cases |
| --- | --- |
| Navigation fixture | GET/POST/redirects; history state and fragments; BFCache; failed loads; named popups; opener/postMessage/noopener/COOP; blank popup documents; window.close; beforeunload. |
| Storage/offline fixture | HTTP validators and no-store; cookie flags; localStorage/IndexedDB/sessionStorage; service-worker registration, update and unregister; offline reload; quota/eviction; all-data and per-site deletion. |
| Privacy fixture | Normal versus private A/B windows; private close/reopen; private downloads; extension queries; auxiliary network fetches; suggestion leakage; relaunch after force quit; sync payload inspection. |
| Permission fixture | Camera/microphone/location allow/refuse; OS refusal/revocation; embedded origins; active-capture stop; location watches; simultaneous prompts; background tab requests; navigation while a prompt is shown. |
| Meeting fixture | Camera call, audio-only call, screen-only share, system-audio share where supported; background tab; memory pressure; device disconnect; sleep/wake; VPN/network transition; window close. |
| Media/hardware fixture | HTML audio/video and Web Audio; muted video; multiple players; media keys; PiP/AirPlay; captions; protected streams; supported headphones; spatial Off/Fixed/Head Tracked; stereo versus verified multichannel/Atmos. |
| Download fixture | Blob/data/form downloads; auth and redirects; resume; segmentation and fallback; renamed files; quarantine/origin attributes; collision and disk-full; private cleanup; sandbox destination grants. |
| Recovery fixture | Quit immediately after an edit; interrupt between snapshot writes; corrupt/truncate a file; old schema; renderer crash; crash during download; relaunch with 100 tabs; no private restoration. |
| Desktop/accessibility fixture | Command/middle/Shift-click; find/print/export; first-responder shortcuts; IME and VoiceOver; focus after sheets; fullscreen; multiple displays; high contrast/reduced motion; UI overlays at minimum window size. |
| Distribution fixture | Exported Developer ID app, notarization, update signature verification, sandboxed Sparkle helpers, failed update, rollback/recovery policy, oldest supported OS, and latest stable OS. |

Record macOS version, WebKit/Safari version where relevant, Astra build, normal/private mode, extension state, hardware, actual outcome, and reproduction steps. A useful diagnostic record should not include cookies, credentials, private URLs, or page contents by default.

## Implementation order

1. **Resolve required feasibility gates:** website Web Push hosting, service-worker/offline behavior, screen-sharing protection, and spatial audio on real hardware. Record exactly which mandatory paths public WKWebView can supply. Do not switch engines before these results exist.
2. **Close P0 trust gaps:** quarantine, deliberate HTTP/HTTPS policy, origin/security UI, coherent snapshots, recovery semantics, private isolation, and non-destructive lifecycle rules.
3. **Complete everyday browser workflows:** find, print/PDF/archive, Open File, full desktop link gestures, history deletion/import/export, permission management, and reliable prompts.
4. **Complete identity and media integration:** passkeys/AutoFill validation, OS authentication sessions, download authentication, payment compatibility, tab mute/audio indicators, Now Playing/media keys, PiP/AirPlay, and the spatial acceptance matrix.
5. **Validate extensions, sync, and releases:** supported-API declaration, permission/update lifecycle, conflict/deletion tests, diagnostic redaction, signed/notarized release updates, and the supported OS matrix.
6. **Add P2 capabilities only when required by the product:** PWA installation, profiles, enterprise controls, translation, or additional native integrations.

## What this research changes

The previous implementation established a foundation; it did not establish industry-browser parity. The remaining work is not a collection of feature toggles. It is a combination of missing desktop workflows, stricter data/lifecycle guarantees, host integrations, and compatibility gates that public WebKit may not expose.

Spatial audio is explicitly retained as a requirement. Website Web Push remains unresolved. Service-worker offline behavior, spatial output, screen sharing, password/payment flows, and distribution behavior remain unverified. No production source was changed as part of this research.


## Implementation ledger — 1 October 2026

The desktop implementation has been extended substantially. These statuses describe code and build verification, not runtime certification. Mobile UI parity, engine replacement, deployment, and live app operation were outside this execution.

| Area | Implemented source work | Verification / remaining boundary |
| --- | --- | --- |
| Snapshot integrity | One atomic, versioned browser-state file; last-good backup; preservation of corrupt/future state; legacy migration and cleanup. | App and tests compile. Corruption/recovery checks are written; not executed. |
| Native restoration | Conditional use of public interaction-state data, encrypted with AES-GCM and a device-only Keychain key, authenticated against the saved URL. Unsupported/unreadable state falls back to URL loading. | No raw form-state blob is synced or saved for private sessions. Cross-relaunch native behavior still requires runtime verification. |
| Private sessions | Isolated stores, permissions, favicon/download state, disabled extension actions, no sync, and idempotent close/quit cleanup. | Privacy checks are written. Abnormal-termination behavior still requires app testing. |
| Lifecycle | Native idle suspension retained; memory pressure drops previews instead of destroying pages. Dirty state remains conservative until a navigation commits. Editable-input changes invalidate restoration snapshots. Closing/quit waits for saves and surfaces actual save failures. | Screen-sharing and complex editor acceptance cases remain runtime tests. |
| File/download security | Quarantine enabled; metadata applied before normal and assembled downloads become completed files; resumed paths retained; asynchronous filename lookup revalidates item identity. | File attributes and signed-release behavior need runtime inspection. |
| Download authentication | Shared native authentication prompts for pages and downloads; protocol checks and confirmation on HTTPS-to-HTTP download redirects. | Provider/proxy/client-certificate behavior remains engine-dependent and unverified. |
| Desktop commands | Find/next/previous, Open File, print, PDF, source, and web-archive export; portable JSON browsing-data and Netscape HTML bookmark import/export. | Compile-verified. HTML import intentionally handles standard quoted Netscape anchors, not arbitrary HTML documents. |
| Desktop link gestures | Command-click and middle-click load background tabs; Shift selects the new tab. Shift-only peeks remain. Popup gestures retain the supplied WebKit configuration; requests keep their original headers. | Gesture-decision checks compile. Real pointer, opener, and focus behavior remain fixture acceptance tests. |
| History | Independent visit records and title updates; individual deletion; clearing without disabling live native back/forward; retention choices; private exclusion. Deletion also removes obsolete legacy data and relevant backup history. Clear/delete updates every open normal window sharing the session, and shared-state application preserves cleared-history policy on retained live tabs. | Records stay local. Current open-page URLs can still be synced as tabs; navigation histories and restoration blobs are excluded. |
| Identity integration | macOS authentication-session handler, HTTPS/custom callback matching, initial headers, ephemeral-session isolation, cancellation, and startup behavior for authentication launches. | Generated capability dictionaries verified. Real requesting-app/provider flows remain untested. |
| Transport/privacy | Web-content-only ATS exception; explicit HTTPS-first policy; Global Privacy Control; native fraud warnings; committed-origin/connection panel; Ask/Allow/Block controls. | Generated plist structure verified. Site compatibility and actual provider behavior need runtime tests. |
| Prompt/bridge safety | Per-window prompt ordering; stale-document cancellation; canceled prompts are not persisted as refusals. Closing a controller invalidates pending requests; external-application prompts and upload choosers cancel after navigation or close. Browser scripts moved to an isolated content world and scroll messages reject non-finite values. | Source-reviewed and compiled. Prompt concurrency fixtures are provided. |
| Media card | Native pause, capture stop, Media Session title/artist where available, paused-card retention, and permitted native AirPlay. | Full native audible-state/mute control remains a public-API boundary; system Media Session/PiP and spatial output require acceptance tests. |
| Extensions | Private action paths blocked; archive size bounds; declared unavailable native-messaging APIs; permission-summary approval records and review when requested access changes. | Extension/provider compatibility and updates remain runtime tests. |
| Sync | Bounded retries of idempotent requests, network-return retry, expired-session handling, payload/structure limits, and protection of active local tabs. Local files, file-access bookmarks, native restoration blobs, and navigation histories are excluded from outgoing tab state. | Existing client/server merge contract retained. No end-to-end encryption or server security certification is claimed. |
| Diagnostics | Explicit copy action with app/OS/engine and failure categories; URLs, tokens, page contents, and form values omitted. | Source-reviewed. No telemetry service was added. |
| Verification infrastructure | Swift Testing target wired into the desktop scheme; local website fixture and range-download server; fixture JavaScript bundled and Python syntax checked. | App and test bundle compile. No test execution, browser automation, or hardware test was performed. |
| Updates | Sparkle's sandbox installer service enabled using its documented key. | The Xcode entitlement helper rejected the documented installer Mach-lookup exception as unavailable. No manual entitlement workaround was applied. Installation remains an unresolved signed-build gate. |
| User-selected file access | Security-scoped bookmark creation/resolution is conditional; read access is narrowed to the selected file. | The Xcode helper rejected the bookmark entitlement. Persistent access remains conditional and unverified; unavailable bookmark data falls back to the saved URL. |

### Gates that remain unresolved

- Website Web Push hosting: the installed public SDK still exposes no hosting integration used by this implementation. No Notifications/Push API shim or native-notification substitute was added.
- Spatial audio: website audio stays on WebKit's native path. The fixture covers HRTF positioning; fixed spatialization, Atmos, and head tracking remain required hardware acceptance cases.
- Service-worker/offline parity, passkeys/AutoFill, screen capture, commercial DRM, Apple Pay, and provider-specific login acceptance require runtime results. Source/build checks do not establish these capabilities.
- The documented bookmark and Sparkle Mach-lookup entitlements were rejected by the available Xcode integration. Their corresponding runtime integrations cannot be marked complete.
- The release workflow now requires Developer ID archive/export, signed-capability validation, accepted notarization, and stapling before publication. Credentials, actual distribution artifacts, and complete signed-update behavior remain unverified and unprovisioned. The missing bookmark/Sparkle entitlements intentionally block publication. See [desktop release pipeline](desktop-release.md). No release was published and no push occurred.

The implementation is a stronger desktop foundation. The full parity objective remains incomplete until these gates and the runtime acceptance matrix are resolved.
