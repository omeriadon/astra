# Astra browser implementation roadmap

Prepared 1 October 2026. Status: planning only. Contains 37 task packets. No implementation agents, branches, worktrees, commits, or releases have been created by this planning task.

## Goal and protected scope

Complete the browser product around WebKit: navigation policy, tabs and windows, persistence, user data, downloads, permissions, browser chrome, privacy, integrations, and recovery. Every work package below has a separate branch and worktree, a bounded handoff, dependencies, and acceptance criteria.

Preserve Astra's current architecture, spaces, peeks, Mini Astra, visual conventions, existing user data, and native WebKit behavior. Extend the existing subsystem before adding another one. Implement the remaining behavior, rather than rebuilding features that already exist.

WebKit and the OS remain responsible for rendering, JavaScript, the DOM, web storage engines, protocol cookies/cache, networking, DNS, TLS/certificate validation, codecs, web security enforcement, webpage accessibility, and native media playback. No engine replacement, custom password cryptography, Chrome API emulation layer, or speculative framework is included. Optional features remain in the roadmap with explicit gates; their presence here is not an instruction to enable or ship them.

## Current source baseline

This is a source-based inventory, not a runtime audit. Read the latest source at dispatch time. The earlier findings in [desktop browser infrastructure](../desktop-browser-infrastructure.md) predate substantial implementation; its **1 October implementation ledger** is the relevant historical baseline. The checkout changed during planning: test sources, browser fixtures and release workflow/scripts seen at initial inspection are absent at final validation, while the project still references the test target. Task 00 must reconcile that mismatch; this plan does not recreate those files or assume their removal was accidental.

| Boundary | Existing source and behavior | Work still to establish |
| --- | --- | --- |
| Browser/window model | `Browser`, `BrowserWindowRegistry`, workspace/space models; tabs, pins, folders, peeks, shared normal-window state | Explicit window/session restoration semantics; reliable ownership across every entry point |
| Page lifecycle | `BrowserTab`, `BrowserController`, `BrowserWebView`; lazy view creation, manual hibernation, history, observation, media/capture guards | Stale callback invariants, practical restoration limits, safe memory policy |
| Navigation | `BrowserAddress`, controller navigation/UI delegates; Google URL parsing, browser link gestures, popups, external-app prompts, native universal-link path | Configurable search, unified policy coverage, unsupported/internal URL boundaries |
| Persistence | `BrowserPersistence`; atomic versioned JSON snapshot, last-good backup, legacy migration; encrypted restoration store | Recovery and migration acceptance, startup choices, window records, reset semantics |
| User data | Independent visits, bookmarks, history UI, bookmark UI, HTML/JSON interchange, favicon store | History aggregation/time ranges; bookmark organization; cache lifecycle |
| Downloads and website UI | Native downloads, resumed/segmented paths, quarantine, download sidebar; upload chooser, dialogs, authentication prompts | Destination preferences, collision/control coverage, permission policy and platform gaps |
| Private browsing | Separate nonpersistent store and session services for each private window | Exhaustive persistence/sync/extension/cleanup checks |
| Permissions and settings | Origin/top-origin camera, microphone and location decisions; site panel, website-data controls, Defaults-backed preferences | Capability feasibility, complete settings coverage, defaults/migrations and per-site preference policy |
| Extensions and privacy | Web Extension manager, install packages, permission summaries; HTTPS-first, GPC, native fraud warning configuration | Supported compatibility matrix, updates and per-site access; optional blocker/reputation gates |
| Desktop services | AppKit window/menu shell, find/zoom, exports/print, browser auth-session handler, default-browser controls, Sparkle | Menu synchronization, OS events, signed update acceptance, unresolved capabilities |
| Sync and verification | Existing account/sync client and merge/tombstone logic; project test-target references remain, but test/fixture sources are currently absent | Baseline reconciliation; server contract/security gates; meaningful checks and hardware/provider acceptance |

Normal windows currently share website data and session services. Spaces are tab organization, not profiles. Private windows are independently isolated. Preserve these defaults. The current controller guard does not establish screen-only capture safety; automatic destructive hibernation was removed in the implementation ledger. Do not reinstate it from the original checklist without a supported protection path.

The app project currently declares macOS and iOS 27 deployment targets. Recheck SDK/platform availability before using an API. Existing source or an API name is not proof that a feature works in the deployed framework.

The later [Web Push and application-link assessment](../web-push-and-app-links.md) records the current public-hosting limit and the implemented macOS link policy. Read it for tasks 02 and 05; revisit its feasibility conclusion only when relevant SDK/API conditions change.

## Architecture contracts

| Responsibility | Owner | Invariant |
| --- | --- | --- |
| Organization and selection | `Browser` / workspace models | Stable IDs; one selected live or restorable tab; organization stays consistent after close, transfer, sync and restore |
| Tab reconstruction | `BrowserTab` / `OpenTab` | Capture recoverable state before releasing a controller; explicit fallback when native restoration is unavailable |
| WebView and page state | `BrowserController` | A view belongs to one tab/peek and session; switching tabs does not recreate it; old callbacks cannot affect a replacement document |
| Storage/privacy services | `BrowserWebSession` | Every service resolves through the correct session; private work avoids normal singletons and disk/sync persistence |
| Durable state | `BrowserPersistence` and existing stores | Versioned validated data; coherent saves; preserve unreadable data; deleting history also handles recoverable backup copies |
| Prompts | `BrowserWebsiteUI` / platform presenter | Ordered per window; complete callbacks exactly once; cancel on navigation, close or lost ownership |
| Browser chrome | Current shell and controller bindings | URL/title/progress/find/zoom/security/capture reflect the selected tab's active controller, including peeks |
| External input | Relevant boundary owner | Validate untrusted URLs, imported documents, extension archives, script messages, network/sync payloads and filenames |

Split delegate responsibilities only where an actual change requires a smaller ownership boundary. Do not replace the controller with a generic coordinator framework. Preserve the supplied WebKit configuration for popup creation and original requests for POST/header-sensitive navigation.

## Work packages

IDs, branch suffixes and packet filenames are stable. Every branch uses `astra/roadmap/<ID-slug>` and every worktree uses `../astra-worktrees/<ID-slug>`. The prerequisites below must be merged before starting a packet. A gate applies to the named optional part, not automatically to the whole packet.

| ID / packet | Priority | Prerequisites | Gate or limit |
| --- | --- | --- | --- |
| [00-baseline](tasks/00-baseline.md) | P0 | None | Establish committed baseline and supported capability ledger |
| [01-lifecycle](tasks/01-lifecycle.md) | P0 | 00 | Destructive hibernation requires capture/draft protection |
| [02-navigation-policy](tasks/02-navigation-policy.md) | P0 | 01 | Universal-link controls limited to supported public APIs |
| [03-persistence-restoration](tasks/03-persistence-restoration.md) | P0 | 01 | Native restoration is best effort; preserve URL fallback |
| [04-private-browsing](tasks/04-private-browsing.md) | P0 | 03 | Separate session per private window remains the default |
| [05-permissions](tasks/05-permissions.md) | P0 | 04 | Web Push, clipboard, display capture and sensors require feasibility checks |
| [06-failures-offline](tasks/06-failures-offline.md) | P0 | 02 | No automatic replay of non-idempotent requests |
| [07-tabs-spaces](tasks/07-tabs-spaces.md) | P1 | 03, 04 | Cross-window transfer must preserve session boundaries |
| [08-windows-os-restoration](tasks/08-windows-os-restoration.md) | P1 | 07 | Preserve current shared normal-window behavior |
| [09-history](tasks/09-history.md) | P1 | 03, 04 | Local visit history; existing sync excludes it |
| [10-bookmarks-reading-list](tasks/10-bookmarks-reading-list.md) | P1 / P2 | 03 | Reading list/offline snapshots are optional |
| [11-favicons](tasks/11-favicons.md) | P1 | 04 | Session-scoped privacy and bounded storage |
| [12-downloads](tasks/12-downloads.md) | P1 | 02, 04, 05 | Resume only where supported; preserve quarantine |
| [13-uploads-auth-challenges](tasks/13-uploads-auth-challenges.md) | P0 / P1 | 02, 04, 05 | Client certificates and capture/upload integrations are platform-dependent |
| [14-address-search-config](tasks/14-address-search-config.md) | P1 | 04 | Remote suggestions require explicit privacy behavior |
| [15-address-intelligence](tasks/15-address-intelligence.md) | P1 | 09, 10, 14 | Website search-engine discovery and clipboard detection are optional |
| [16-chrome-find-zoom](tasks/16-chrome-find-zoom.md) | P1 | 01, 05, 07 | Find counts and capture state must be supported, not fabricated |
| [17-keyboard-menus](tasks/17-keyboard-menus.md) | P1 | 08, 16 | Commands target the focused window and current page |
| [18-site-data-preferences](tasks/18-site-data-preferences.md) | P1 | 03, 04, 05, 09, 16 | Website-data API granularity must be disclosed |
| [19-start-page](tasks/19-start-page.md) | P1 | 07, 09, 10, 11, 15 | Widgets/privacy reports are optional |
| [20-security-reputation](tasks/20-security-reputation.md) | P0 / P2 | 02, 05, 06, 18 | Additional reputation provider requires a product/privacy decision |
| [21-content-blocking](tasks/21-content-blocking.md) | P2 | 18, 20 | Direct rule-list subsystem only if selected; coordinate installed blockers |
| [22-extensions](tasks/22-extensions.md) | P1 / P2 | 02, 05, 07, 08, 21 | Public Web Extension support only; unsupported APIs stay declared |
| [23-credentials-browser-auth](tasks/23-credentials-browser-auth.md) | P0 / P1 | 13 | AutoFill/passkey/provider acceptance requires real platform evidence |
| [24-media](tasks/24-media.md) | P1 | 01, 05, 16 | Audible/mute/spatial controls depend on exposed APIs and hardware |
| [24a-picture-in-picture](tasks/24a-picture-in-picture.md) | P1 required | 17, 24 | Native PiP, browser controls, originating-tab restoration and playback protection; required capability gates remain open until verified |
| [25-page-tools-context-drag](tasks/25-page-tools-context-drag.md) | P1 | 12, 13, 16, 17 | Save-resource completeness is an optional commitment |
| [26-reader-translation-source](tasks/26-reader-translation-source.md) | P2 | 16, 18, 25 | Reader/translation need capability/provider choices |
| [27-internal-urls](tasks/27-internal-urls.md) | P1 / P2 | 02, 03, 17, 20 | Existing native pages remain usable without a custom scheme |
| [28-settings](tasks/28-settings.md) | P1 | 14, 18, 19, 21, 22, 24, 24a, 26, 27 | Show only supported and selected features |
| [29-sync](tasks/29-sync.md) | P1 / P2 | 03, 04, 07, 09, 10, 28 | Server contract, history sync and E2EE are separate gates |
| [30-profiles](tasks/30-profiles.md) | P2 | 04, 18, 22, 28, 29 | Explicit profile product decision required |
| [31-macos-automation-webapps](tasks/31-macos-automation-webapps.md) | P1 / P2 | 08, 17, 23, 27, 28 | PWA, Handoff, Spotlight and automation are optional |
| [32-ios-integration](tasks/32-ios-integration.md) | P1 follow-up | 17, 23, 24, 24a, 25, 28, 31 | Entitlements, background limits and scene behavior need platform checks |
| [33-updates-distribution](tasks/33-updates-distribution.md) | P0 release | 28, 31, 32 | Signing, notarization and sandboxed update acceptance |
| [34-diagnostics-performance](tasks/34-diagnostics-performance.md) | P1 | 06, 12, 22, 24, 24a, 29 | Measurement requires later runtime authorization |
| [35-accessibility-integration](tasks/35-accessibility-integration.md) | P0 release | All selected packets | Runtime/hardware release gates remain distinct from compile checks |

P0 means data loss, security boundaries, feasibility or release blockers. P1 means the everyday browser baseline. P2 means a feature selected for a later milestone. Priority does not override prerequisites. A skipped optional packet produces a gate decision and no speculative code; downstream work consumes that decision.

## Milestones and merge order

Use numerical order as the default merge queue, with 24a immediately after 24. It satisfies the dependency graph and keeps shared files under one writer. Independent packets may start earlier only after all prerequisites have merged and the dispatcher confirms disjoint write ownership.

| Milestone | Packets | Exit condition |
| --- | --- | --- |
| Foundation | 00–06 | Ownership, navigation, persistence, privacy, permission and failure invariants established; capability limits recorded |
| Everyday browsing | 07–19 | Tabs/windows, history/bookmarks/icons, downloads/uploads, address/search, chrome and commands implemented against the existing architecture |
| Protection and advanced services | 20–27, including 24a | Security, blocking, extensions, identity, media, required PiP, page tools and internal routing completed or explicitly gated |
| Product/platform completion | 28–34 | Settings wired, current sync preserved/hardened, optional profiles/integrations decided, mobile parity addressed, release/performance limits recorded |
| Integration | 35 | Selected scope reconciled, diagnostics/builds reviewed, privacy/data compatibility accounted for, remaining runtime gates enumerated |

The existing repository constraint permits one implementation Luna agent, or two for genuinely independent scopes. It also normally requests direct implementation in this Browser project. This request establishes the worktree-based handoff plan; when these packets are later explicitly dispatched to subagents, each receives its own worktree. No agent starts merely because this roadmap exists. Use a primary Sol agent for analysis, architecture, review and final reporting; use `gpt-6-luna` with medium reasoning for these behavior-tracing packets. Low reasoning fits bounded mechanical follow-ups only.

Suitable parallel candidates, subject to file reservations and merged prerequisites: 10 with 11; 13 with 15; 25 with 29. PiP runs after 24 and reserves its shared controller/media/menu files. These are candidates, not permission to edit shared files simultaneously.

## Coverage of the supplied checklist

| Checklist area | Owning packet(s) |
| --- | --- |
| Navigation, policy, special URLs, external apps, universal links | 02, 14, 16 |
| Tabs, hibernation, pins/favorites, groups/workspaces | 01, 07 |
| Windows, popups, geometry, fullscreen, OS events | 02, 08, 24, 32 |
| Session persistence, crash restore, startup, migrations | 03, 08, 28 |
| Browser history and address-bar history deletion | 09, 15 |
| Bookmarks/favorites, HTML import/export, reading list | 10, 19, 29 |
| Favicons, site identity, icon cache | 11, 20 |
| Downloads, names/destinations, permissions, file security | 05, 12 |
| Uploads, authentication challenges, browser auth sessions | 13, 23 |
| Permissions, website data, private browsing, site preferences | 04, 05, 18 |
| Credentials, AutoFill, passkeys | 23 |
| Find, zoom, chrome state coordination | 16 |
| Reader, appearance overrides, source, translation | 25, 26 |
| Content blockers, extensions | 21, 22 |
| Developer tools, context menus, drag/drop | 07, 17, 25, 34 |
| Keyboard, application menus, shortcut conflicts | 17, 32 |
| Address intelligence, search engines/configuration | 14, 15 |
| Security UI, fraud/malicious-site protection | 20 |
| Start page, themes, recent/frequent pages | 19 |
| Printing, saving/exporting pages, sharing | 25 |
| Web apps/PWA, automation, OS/default-browser integration | 31, 32 |
| Media, required picture-in-picture, process/navigation failures, network awareness | 06, 24, 24a, 32 |
| Settings and their persistence/reset/migration | 03, 18, 28 |
| Data persistence/migrations, sync, profiles | 03, 29, 30 |
| Updates, crash reporting, diagnostics | 33, 34 |
| Memory, performance, WebView lifecycle, delegate ownership | 01, 34 |
| Internal pages, custom URLs, privilege separation | 27 |
| Compatibility workarounds, UA, website preferences | 18, 34 |
| Browser accessibility and final platform acceptance | Every packet, then 35 |
| Engine-owned functionality in “Things you should not build” | Protected scope; fixture acceptance only, primarily 35 |

## Verification and completion states

The Browser project currently limits agent verification to source inspection and Xcode MCP diagnostics/builds when needed. Agents must not launch or operate Astra with computer-use tools. Running hosted tests or fixtures also executes the app, so leave execution pending under this restriction. Written tests can be compiled. Never use `xcodebuild`. For an actual Swift package check, use `set -o pipefail; swift build 2>&1 | xcsift -f toon -w` or the equivalent `swift test` pipeline.

Reconcile the project's `astraInfrastructureTests` references in task 00. The earlier `astraInfrastructureTests/astraInfrastructureTests.swift` and `tests/browser-fixtures/README.md` files are currently absent. Reuse available verification assets at dispatch time; add only the smallest needed check/fixture within selected implementation scope, rather than restoring a historical suite as unrelated work. Give packets unique check assets. A small UI-only change requires source inspection and the smallest relevant diagnostic, not a ceremonial full build.

Record each packet as **planned**, **in progress**, **source complete**, **build verified**, **runtime verified**, **gated**, or **blocked**, with evidence. “Blocked” names a concrete dependency or unavailable capability. A compile result cannot establish runtime compatibility. Merge readiness means bounded source work and available checks pass; it does not mean release readiness.

The final release gate includes crash/corrupt-state recovery, normal/private isolation, stale prompts, popup opener/POST behavior, screen-only capture protection, permission reset, uploads/download resume/quarantine, identity/provider compatibility, signed updates and platform accessibility. PiP is required: entry/exit, originating-tab restoration, playback through tab/window/scene changes and safe close/hibernation behavior need acceptance evidence on macOS and iOS. Spatial audio, passkeys/AutoFill, service-worker/offline behavior, commercial DRM, Apple Pay and Web Push hosting retain the unresolved capability/runtime gates recorded in the existing infrastructure ledger. Do not fabricate substitutes or claim they passed.

## Dispatch material

Use [the dispatch and worktree procedure](dispatch.md) plus exactly one packet from `tasks/`. The packet includes source entry points, write ownership, required behavior, acceptance cases and verification. Record results in the packet-specific handoff report described by the dispatch procedure. The user merges reviewed branches later; implementation agents never push or merge them.
