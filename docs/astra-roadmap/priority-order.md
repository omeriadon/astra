# Remaining packet priority order

The user requested ordering the remaining work from most to least important. This is the active execution queue after packet07 source review. It preserves packet dependencies and treats selected scope as work, not permission to skip it.

The packet07 `astra` / `My Mac` build remains the first pending app-build gate and should run when Xcode MCP transport is available. Its temporary outage does not pause independent source work. Packet12 is already active in its separate worktree; finish it and review shared-file boundaries before packet13. Packet13 source checks may proceed while its own app compilation is explicitly gated on Xcode MCP availability. Integrate packet12 exactly once into the later packet08 worktree after its source review and available compiler gate; do not treat its separate branch as cumulative yet.

| Order | Packet | Priority reason and dependency notes |
| --- | --- | --- |
| Active | [12-downloads](tasks/12-downloads.md) | Finish the active data/file safety work first; preserve quarantine, path validation and partial-file cleanup. |
| 1 | [13-uploads-auth-challenges](tasks/13-uploads-auth-challenges.md) | Close file-picker lifetime and authentication ownership paths before broader everyday features. Prerequisites02,04,05 are reviewed. |
| 2 | [09-history](tasks/09-history.md) | User-selected history sync/cache scope consumes the existing timestamped merge contract. Prerequisites03,04 are reviewed. |
| 3 | [08-windows-os-restoration](tasks/08-windows-os-restoration.md) | Establish reliable window and OS restoration after tab organization and history foundations. Prerequisite07 is source reviewed; its Mac app build remains open. Combine reviewed12 here exactly once. |
| 4 | [10-bookmarks-reading-list](tasks/10-bookmarks-reading-list.md) | Implement the selected local/synced library, reading-list and offline snapshot scope, subject to precise API and storage gates. |
| 5 | [16-chrome-find-zoom](tasks/16-chrome-find-zoom.md) | Finish everyday page controls before menu and settings integration. |
| 6 | [18-site-data-preferences](tasks/18-site-data-preferences.md) | Establish site data and per-origin preferences before higher-level security/settings work. |
| 7 | [20-security-reputation](tasks/20-security-reputation.md) | Deliver security behavior after navigation, permission, failure and site-preference foundations. |
| 8 | [23-credentials-browser-auth](tasks/23-credentials-browser-auth.md) | Validate native credential and authentication behavior before standalone site apps and release integration. |
| 9 | [17-keyboard-menus](tasks/17-keyboard-menus.md) | Consolidate focused-window command routing after window, chrome, permission and auth ownership is settled. |
| 10 | [31-macos-automation-webapps](tasks/31-macos-automation-webapps.md) | Implement the user's required standalone website Dock apps after window/menu/auth foundations. This includes ordinary manifest-free websites, a real independent `.app`/Dock identity, Mini Astra-style top-bar-only windows, Command-S top-bar toggling, current-tab menu creation and a management page. It does not depend on the optional `astra://` scheme or the later settings audit. |
| 11 | [15-address-intelligence](tasks/15-address-intelligence.md) | Add address intelligence after history, bookmarks and configured search are stable. |
| 12 | [21-content-blocking](tasks/21-content-blocking.md) | Implement selected blocking behavior on top of the site preference and security decisions. |
| 13 | [22-extensions](tasks/22-extensions.md) | Validate extension integration after browser commands, windows and blocker interaction are established. |
| 14 | [27-internal-urls](tasks/27-internal-urls.md) | Complete native page routing and evaluate the optional custom internal scheme. Packet31's LaunchServices website app launch does not complete or require this packet. |
| 15 | [25-page-tools-context-drag](tasks/25-page-tools-context-drag.md) | Add page tools after downloads, uploads, chrome commands and windows are settled. |
| 16 | [19-start-page](tasks/19-start-page.md) | Reconcile the start page after its history, bookmarks, favicon and address-intelligence inputs exist. |
| 17 | [26-reader-translation-source](tasks/26-reader-translation-source.md) | Add reader, translation and source views after page tools and site settings. Provider gates remain explicit. |
| 18 | [28-settings](tasks/28-settings.md) | Perform the final settings schema/navigation audit after selected features, including packet31's installed-site management page, are available. |
| 19 | [32-ios-integration](tasks/32-ios-integration.md) | Reconcile mobile scenes, entitlements and platform-specific behavior after shared feature work. |
| 20 | [34-diagnostics-performance](tasks/34-diagnostics-performance.md) | Measure the selected product after feature integration; runtime measurement still needs authorization. |
| 21 | [30-profiles](tasks/30-profiles.md) | Implement selected profile scope after shared/private sessions, settings, extensions and sync contracts, subject to precise API, storage and privacy gates. |
| 22 | [33-updates-distribution](tasks/33-updates-distribution.md) | Close signing, notarization and updater gates near release, after settings, website apps and iOS integration. |
| 23 | [35-accessibility-integration](tasks/35-accessibility-integration.md) | Run the aggregate release accessibility gate last because it depends on every selected packet. Its final position is dependency-driven, not a lower requirement. |

Dependencies remain gates. Do not start an item while a required predecessor or shared-file reservation is unresolved. Packet31's explicit dependencies are **08, 17, 23**; packet28 now also depends on31 so its final settings audit includes installed-site management. Packet27 remains separately scheduled for internal page routing and optional scheme support.
