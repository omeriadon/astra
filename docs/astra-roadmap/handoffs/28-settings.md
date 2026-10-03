# 28-settings

Task / selected scope: Packet28 baseline settings reconciliation. Preserve feature-owned settings UIs, add an explicit portable/device-only schema contract, and add a non-destructive reset path.

Branch / baseline: `astra/roadmap/28-settings`; baseline packet27 HEAD `ec9a824b7fadf6b3162d5f065ae6d83b1feba3a0`, itself based on the cumulative packet21/29 source state. Packets22 and26 remain separate merge prerequisites but do not introduce additional general settings keys in their current selected scopes.

Status: source implementation complete; Xcode build and UI/runtime propagation checks remain for the user's Mac.

Commits: schema/reset policy `8e05277aecc57dbaf5be1960da66c19969c2e9f0`; Advanced settings reset UI `d605bf5e5aace85d9e6659f0f0634bcaa4405e57`; schema check `c74859c2b0fcae6a0dc6bfd720e8a4b8881ffec7`.

Changes:

- `BrowserSettingsSchema` makes task29's synchronization contract explicit: `Defaults.Keys.syncedSettingNames` is the portable allowlist; local filesystem bookmarks, account endpoint, local sidebar/Mini Astra/developer state are separately enumerated as device-only.
- A consistency guard verifies portable and device-only/forbidden sets cannot overlap. In particular, `syncServerURL`, `downloadsFolderBookmark` and local sidebar state are forbidden from portable preference sync.
- `resetBrowserSettings()` restores general browser preference defaults including startup/homepage, HTTPS-first/GPC, retention/search/start-page preferences, site zoom settings, theme, download prompting/renaming, mailto behavior, quit behavior, address style, peek/zoom defaults and local interface/developer settings.
- Reset deliberately does **not** clear browsing history records, cookies/website data, bookmarks/reading list, downloaded files, extension packages, credentials, account identity or sync data. This keeps settings reset distinct from destructive clear-data operations.
- Advanced Settings exposes the reset behind a confirmation dialog and states exactly which data is preserved.
- Existing `Defaults` keys remain authoritative; this packet does not create a second settings storage system.

Task29 timestamp contract: every portable name continues to flow through the existing `syncedSettingNames` allowlist and packet29's timestamped settings cache/merge. No device-only secret/path was added to that allowlist.

Verification asset: `checks-28-settings.swift` asserts schema version, portable/device-only disjointness, required portable search/start/home keys, and explicit exclusion of sync endpoints/download-folder bookmarks. The user's local build should additionally exercise `resetBrowserSettings()` through the UI and verify live controllers observe Defaults-backed changes as expected.

Pending integration/runtime cases:

- Build macOS and iOS targets after merging prerequisite packet branches.
- Change each settings section and verify active windows/controllers update without page recreation or lost drafts.
- Exercise reset and verify browsing data/account state remain intact.
- Confirm download-folder security-scoped state returns to the default location after reset.
- Re-run packet29 stale/newer timestamp merge tests with the final portable setting set.

Data/privacy/migration impact: no storage format migration. Reset is user-initiated and does not perform browsing-data deletion. Portable settings remain allowlisted; machine paths/account endpoint stay local.

Merge prerequisites: packets14,18,19,21,22,24,24a,26,27,29 as selected. User-controlled integration only.
