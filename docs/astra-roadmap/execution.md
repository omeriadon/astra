# Execution ledger

User scope: execute all 37 packets, including PiP and optional feature scopes. Concrete public API/provider/signing limitations remain unresolved gates until evidence resolves them.

Implementation model: `gpt-6-luna`, medium reasoning; one active writer, up to two only for reserved disjoint scopes. Every packet has a dedicated worktree/branch. No pushes or merges.

Original checkout: `/Users/omeriadon/Documents/Xcode_App_Library/browser`.
Original HEAD: `8ba68083157ede8bca2cac8ea01712aebc02f86b`.
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
| [07-tabs-spaces](tasks/07-tabs-spaces.md) | queued | — |
| [08-windows-os-restoration](tasks/08-windows-os-restoration.md) | queued | — |
| [09-history](tasks/09-history.md) | queued | — |
| [10-bookmarks-reading-list](tasks/10-bookmarks-reading-list.md) | queued | — |
| [11-favicons](tasks/11-favicons.md) | build verified; primary reviewed | 948f8fa; bounded fetch/decoding/cache and hydration guards |
| [12-downloads](tasks/12-downloads.md) | queued | — |
| [13-uploads-auth-challenges](tasks/13-uploads-auth-challenges.md) | queued | — |
| [14-address-search-config](tasks/14-address-search-config.md) | independently reviewed; Mac build and final parser helper checks pass | separate branch source `f63f5b5`, review HEAD `9fa4963`; Mac build20.732s before final helper-only parser correction; combine once in next task worktree |
| [15-address-intelligence](tasks/15-address-intelligence.md) | queued | — |
| [16-chrome-find-zoom](tasks/16-chrome-find-zoom.md) | queued | — |
| [17-keyboard-menus](tasks/17-keyboard-menus.md) | queued | — |
| [18-site-data-preferences](tasks/18-site-data-preferences.md) | queued | — |
| [19-start-page](tasks/19-start-page.md) | queued | — |
| [20-security-reputation](tasks/20-security-reputation.md) | queued | — |
| [21-content-blocking](tasks/21-content-blocking.md) | queued | — |
| [22-extensions](tasks/22-extensions.md) | queued | — |
| [23-credentials-browser-auth](tasks/23-credentials-browser-auth.md) | queued | — |
| [24-media](tasks/24-media.md) | build verified; primary reviewed | 7255d12; public native playback plus scoped player controls; PiP still pending24a |
| [24a-picture-in-picture](tasks/24a-picture-in-picture.md) | queued | — |
| [25-page-tools-context-drag](tasks/25-page-tools-context-drag.md) | queued | — |
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

The user reported invalid HTTPS sync URL errors and missing settings, and required on-device caching and last-updated conflict protection for every synchronized record, explicitly including history, bookmarks, spaces and settings. Packet 29 runs next against existing reviewed implementations; remaining prerequisites will consume its upgraded persistence/merge contract. The original checkout remains unchanged.

Combined baseline: independent navigation, offline/failure and favicon checkpoints were cherry-picked into task03 from the reviewed sync29 branch. Original checkout remains unchanged. Xcode MCP workspace workspace-VvsSm87feh, astra/My Mac, combined build passed in29.643s with no errors.

## User-requested handoff

The user requested finishing the active packet and producing a continuation file instead of starting more work in this context. Eleven packets are source-reviewed; twenty-six remain. Cumulative05 contains ten and independent14 remains on its own branch; combine it in the next task worktree. Read [CONTINUE.md](CONTINUE.md) for the authoritative resume point, worktree rules, remaining work and verification limits. The original checkout has advanced independently since the initial snapshot; do not overwrite or merge it without a new integration instruction.

## Permissions/search close-out

The user requested finishing up. Packets05 and14 are reviewed within their stated source/build limits. No PiP or other next packet was started. Read CONTINUE.md for the cumulative05 baseline, independent14 checkpoint sequence, and next PiP dispatch. Permission decisions are device-only; search configuration joins the existing timestamped portable setting cache. Original checkout and all worktrees remain intact.
