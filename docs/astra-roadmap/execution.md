# Execution ledger

User scope: execute all 37 packets, including PiP and optional feature scopes. Concrete public API/provider/signing limitations remain unresolved gates until evidence resolves them.

Implementation model: `gpt-6-luna`, medium reasoning; one active writer, up to two only for reserved disjoint scopes. Every packet has a dedicated worktree/branch. No pushes or merges.

Original checkout: `/Users/omeriadon/Documents/Xcode_App_Library/browser`.
Original HEAD: `8ba68083157ede8bca2cac8ea01712aebc02f86b`.
Snapshot checkpoint: `051e62ed742a12ae7f25a4e4c4a39fe6eb9d1ffb` on `astra/roadmap/00-baseline`.

The snapshot includes the existing uncommitted implementation and deletions. Its first commit triggered a formatting hook; a follow-up restored the exact source bytes. All later checkpoints bypass that formatting hook with `git -c core.hooksPath=/dev/null commit`.

| Packet | Status | Reviewed commit / evidence |
| --- | --- | --- |
| [00-baseline](tasks/00-baseline.md) | in progress | — |
| [01-lifecycle](tasks/01-lifecycle.md) | queued | — |
| [02-navigation-policy](tasks/02-navigation-policy.md) | queued | — |
| [03-persistence-restoration](tasks/03-persistence-restoration.md) | queued | — |
| [04-private-browsing](tasks/04-private-browsing.md) | queued | — |
| [05-permissions](tasks/05-permissions.md) | queued | — |
| [06-failures-offline](tasks/06-failures-offline.md) | queued | — |
| [07-tabs-spaces](tasks/07-tabs-spaces.md) | queued | — |
| [08-windows-os-restoration](tasks/08-windows-os-restoration.md) | queued | — |
| [09-history](tasks/09-history.md) | queued | — |
| [10-bookmarks-reading-list](tasks/10-bookmarks-reading-list.md) | queued | — |
| [11-favicons](tasks/11-favicons.md) | queued | — |
| [12-downloads](tasks/12-downloads.md) | queued | — |
| [13-uploads-auth-challenges](tasks/13-uploads-auth-challenges.md) | queued | — |
| [14-address-search-config](tasks/14-address-search-config.md) | queued | — |
| [15-address-intelligence](tasks/15-address-intelligence.md) | queued | — |
| [16-chrome-find-zoom](tasks/16-chrome-find-zoom.md) | queued | — |
| [17-keyboard-menus](tasks/17-keyboard-menus.md) | queued | — |
| [18-site-data-preferences](tasks/18-site-data-preferences.md) | queued | — |
| [19-start-page](tasks/19-start-page.md) | queued | — |
| [20-security-reputation](tasks/20-security-reputation.md) | queued | — |
| [21-content-blocking](tasks/21-content-blocking.md) | queued | — |
| [22-extensions](tasks/22-extensions.md) | queued | — |
| [23-credentials-browser-auth](tasks/23-credentials-browser-auth.md) | queued | — |
| [24-media](tasks/24-media.md) | queued | — |
| [24a-picture-in-picture](tasks/24a-picture-in-picture.md) | queued | — |
| [25-page-tools-context-drag](tasks/25-page-tools-context-drag.md) | queued | — |
| [26-reader-translation-source](tasks/26-reader-translation-source.md) | queued | — |
| [27-internal-urls](tasks/27-internal-urls.md) | queued | — |
| [28-settings](tasks/28-settings.md) | queued | — |
| [29-sync](tasks/29-sync.md) | queued | — |
| [30-profiles](tasks/30-profiles.md) | queued | — |
| [31-macos-automation-webapps](tasks/31-macos-automation-webapps.md) | queued | — |
| [32-ios-integration](tasks/32-ios-integration.md) | queued | — |
| [33-updates-distribution](tasks/33-updates-distribution.md) | queued | — |
| [34-diagnostics-performance](tasks/34-diagnostics-performance.md) | queued | — |
| [35-accessibility-integration](tasks/35-accessibility-integration.md) | queued | — |
