# Execution ledger

User scope: execute all 37 packets, including PiP and optional feature scopes. Concrete public API/provider/signing limitations remain unresolved gates until evidence resolves them.

Implementation model: `gpt-6-luna`, medium reasoning; one active writer, up to two only for reserved disjoint scopes. Every packet has a dedicated worktree/branch. No pushes or merges.

Original checkout: `/Users/omeriadon/Documents/Xcode_App_Library/browser`.
Original snapshot HEAD: `8ba68083157ede8bca2cac8ea01712aebc02f86b`. The latest known original-checkout HEAD is recorded in CONTINUE.md; recheck before any later integration.
Snapshot checkpoint: `051e62ed742a12ae7f25a4e4c4a39fe6eb9d1ffb` on `astra/roadmap/00-baseline`.

The snapshot includes the existing uncommitted implementation and deletions. Its first commit triggered a formatting hook; a follow-up restored the exact source bytes. All later checkpoints bypass that formatting hook with `git -c core.hooksPath=/dev/null commit`.

| Packet | Status | Reviewed commit / evidence |
| --- | --- | --- |
| [00-baseline](tasks/00-baseline.md) | build verified; primary reviewed | `2a6932d8aab907302f252d58fcb4a8e22d848fe8`; stale test metadata removed, app builds |
| [01-lifecycle](tasks/01-lifecycle.md) | build verified; primary reviewed | `0c50cc8faf07ee9dca8ac8aef0fe6465b14b8f72`; safe promotion, cleanup and peek session reconstruction |
| [02-navigation-policy](tasks/02-navigation-policy.md) | reviewed; build and pure parser checks pass | `1699f4728632432225c6f88f417681c8f8f8c57a`; hooks assigned05/32 |
| [03-persistence-restoration](tasks/03-persistence-restoration.md) | build verified; primary reviewed | 03a2b05; non-destructive startup, session marker, validated window records; refreshed Mac build25.27s passes |
| [04-private-browsing](tasks/04-private-browsing.md) | build verified; primary reviewed | 49d35738; source close-out `1d89883d105266a1e30e3fa9ca5f50f35ea6ea54`; private session notifications isolated |
| [05-permissions](tasks/05-permissions.md) | primary reviewed; Mac build verified; runtime/API gates open | `75905077`, handoff `f1315876`; scoped grants, prompt ownership, capture revocation, top-site multiple downloads; final Mac build5.913s |
| [06-failures-offline](tasks/06-failures-offline.md) | build verified; primary reviewed | 42a1274; invalidation/retry guards and repeated-crash recovery; combined build passes |
| [07-tabs-spaces](tasks/07-tabs-spaces.md) | source-reviewed; Mac compilation verified in cumulative09 | `b9df976` source; unchanged07 compiled in09 Mac build12.414s; runtime/iOS open |
| [08-windows-os-restoration](tasks/08-windows-os-restoration.md) | primary reviewed; Mac build verified | `4372ae2`, report `2486cc1`; Mac build12.916s; native display/window lifecycle/iOS open |
| [09-history](tasks/09-history.md) | primary source-reviewed; Mac build verified | `b9ff0df`; missing shared-filter return fixed, Mac build12.414s, policy check passes; runtime/iOS open |
| [10-bookmarks-reading-list](tasks/10-bookmarks-reading-list.md) | primary reviewed; Mac build verified | finalc59f6eb, Mac8.037s; native archive/sandbox/iOS gates open |
| [11-favicons](tasks/11-favicons.md) | build verified; primary reviewed | 948f8fa; bounded fetch/decoding/cache and hydration guards |
| [12-downloads](tasks/12-downloads.md) | primary source-reviewed; Mac build verified | corrections `1766a42`, review `647c3ea`; Mac build10.097s; sandbox/native transfer/iOS gates open |
| [13-uploads-auth-challenges](tasks/13-uploads-auth-challenges.md) | primary reviewed; Mac build verified | `96c969d`, `3035af0`, primary `6f3132c`; Mac build8.535s; native/sandbox/client-certificate/iOS gates open |
| [14-address-search-config](tasks/14-address-search-config.md) | reviewed; combined into24a and later cumulative branches | source `f63f5b5`, review `9fa4963`; latest cumulative Mac build23.51s; suggestion/provider runtime open |
| [15-address-intelligence](tasks/15-address-intelligence.md) | primary reviewed; Mac build verified; native runtime gates open | `91501ab`, `fb98be7`, handoff `9a27de4`, primary `39e6530`; exact15 Mac build12.868s; cumulative15 includes reviewed10/16/17 |
| [16-chrome-find-zoom](tasks/16-chrome-find-zoom.md) | primary reviewed; Mac build verified | d9aeeb5, Mac19.443s; combined once in10; native find/focus/iOS gates open |
| [17-keyboard-menus](tasks/17-keyboard-menus.md) | primary reviewed; Mac build verified | 32f26ac, Mac13.075s; combined once in15; keyboard/public inspector/iOS gates open |
| [18-site-data-preferences](tasks/18-site-data-preferences.md) | queued | — |
| [19-start-page](tasks/19-start-page.md) | in progress; focused production checks pass; Mac build pending | source baseline `6a7771d`, pointer `ba47531`; start-page implementation and check are uncommitted |
| [20-security-reputation](tasks/20-security-reputation.md) | queued | — |
| [21-content-blocking](tasks/21-content-blocking.md) | queued | — |
| [22-extensions](tasks/22-extensions.md) | queued | — |
| [23-credentials-browser-auth](tasks/23-credentials-browser-auth.md) | primary reviewed; Mac build verified; signed/provider gates open | source `202d7ac`/`605ef85`/`c5dc24f`, reports `5cb4290`/`a912e6c`, primary `ea29d26`; Mac18.159s |
| [24-media](tasks/24-media.md) | build verified; primary reviewed | 7255d12; public native playback plus scoped player controls; PiP still pending24a |
| [24a-picture-in-picture](tasks/24a-picture-in-picture.md) | reviewed per later handoff; Mac build recorded; runtime/provider/iOS gates open | `d6be8c0` per resume audit, implementation `0322585`; recorded Mac build8.871s, not rerun here |
| [25-page-tools-context-drag](tasks/25-page-tools-context-drag.md) | primary reviewed; Mac build verified; runtime/API gates open | dedicated25 from reviewed23 `ea29d26`; source `4b9cc5b`/`96cfe9f`, handoff `f35abd3`; exact Mac build11.248s, zero errors; iOS build stopped by existing Sparkle failure before task diagnostics |
| [26-reader-translation-source](tasks/26-reader-translation-source.md) | queued | — |
| [27-internal-urls](tasks/27-internal-urls.md) | queued | — |
| [28-settings](tasks/28-settings.md) | queued | — |
| [29-sync](tasks/29-sync.md) | build verified; primary reviewed | `4fcb508245c77871b9faceb248e5b420d72840df`; local cache, endpoint binding, versioned history/settings/record merges and peer preservation |
| [30-profiles](tasks/30-profiles.md) | queued | — |
| [31-macos-automation-webapps](tasks/31-macos-automation-webapps.md) | queued | — |
| [32-ios-integration](tasks/32-ios-integration.md) | queued | — |
| [33-updates-distribution](tasks/33-updates-distribution.md) | queued | — |
| [34-diagnostics-performance](tasks/34-diagnostics-performance.md) | queued | — |
| [35-accessibility-integration](tasks/35-accessibility-integration.md) | queued | — |

## Sync priority override

The user reported invalid HTTPS sync URL errors and missing settings, and required on-device caching and last-updated conflict protection for every synchronized record, explicitly including history, bookmarks, spaces and settings. Packet29 was prioritized and its source work completed before the remaining foundation packets. Later packets consume its reviewed persistence/merge contract; do not dispatch29 again. The original checkout remains unchanged.

Combined baseline: independent navigation, offline/failure and favicon checkpoints were cherry-picked into task03 from the reviewed sync29 branch. Original checkout remains unchanged. Xcode MCP workspace workspace-VvsSm87feh, astra/My Mac, combined build passed in29.643s with no errors.

## User-requested handoff

Historical handoff: packets05 and14 were reviewed, and the prior continuation pointed at PiP. That handoff is superseded by the resumed PiP close-out below. Read [CONTINUE.md](CONTINUE.md) for the current authoritative worktree and next packet. The original checkout has advanced independently since the initial snapshot; do not overwrite or merge it without a new integration instruction.

## Permissions/search close-out

Historical close-out: packets05 and14 were reviewed within their stated source/build limits. At that point PiP had not started. Permission decisions are device-only; search configuration joins the existing timestamped portable setting cache. Original checkout and all worktrees remain intact.

## Resumed PiP dispatch

Task24a started in its own worktree from the latest cumulative05 checkpoint `1739188ecf8ac04049f53dacf0f1b9636c752ea1`. The five reviewed14 integration checkpoints were cherry-picked once, producing combined baseline `a9ba5cb`. Original14 remains intact. One gpt-6-luna implementation worker owns the PiP lifecycle/control files; primary owns review and serialized Xcode verification. A minimal existing menu command is scheduled ahead of17; this does not complete17. The original checkout remains untouched.

## Added user scope: standalone website Dock apps

During resumed24a work, the user explicitly selected standalone website Dock apps for31: any website, Mini Astra-style top-bar-only window, Command-S top-bar toggle, current-tab menu creation, dedicated settings management, and actual app/Dock installation. The detailed packet31 now includes those requirements. This records scope; implementation31 has not started.

## PiP close-out

Packet24a source was reviewed and its combined `astra` / `My Mac` Xcode MCP build passed in 8.871s with zero reported issues in the five changed Swift files. Bun production-script checks, Swift protection-policy checks, and the combined packet14 helper check passed. Implementation checkpoint `0322585358fe2567fb8ff47155187b3225939323`; reviewed handoff checkpoint `a5dbcc4c4f3a98bf30c339fdd53bf40d23f722c9`.

This closes source/build review for the twelfth packet; twenty-five packets remain. PiP runtime acceptance is open: actual entry/exit and native controls, exact automatic return focus, iframe state, provider/DRM/user-activation limits, background/view-detachment behavior and iOS scene/audio behavior were not exercised. Playing or paused media is conservatively protected; browser controls/state inspect main-frame HTML video only. The minimal Navigation menu action was scheduled ahead of17; packet17 remains queued and incomplete. Standalone website Dock apps are required selected scope in packet31; implementation has not started.

## Tabs/spaces and priority queue

Packet07 source is primary reviewed at `03da6a0`; its handoff is `de86f6c`. The production workspace helper, source parsing and whitespace checks pass. Xcode MCP transport closed before diagnostics/build, so the Mac app compile gate remains open; no app/runtime check ran. Thirteen packets are source-reviewed in the cumulative branch; twenty-four remain. Packet12 is active in a separate worktree and has not been reviewed or integrated. Follow [priority-order.md](priority-order.md): resume packet07's app build when Xcode MCP transport is available, continue the already active packet12, then dispatch the ranked queue. Packet31 depends on08,17,23; packet28 also depends on31 so the final settings audit includes installed-site management. Packet27 remains the separate native internal-page/custom-scheme packet.
