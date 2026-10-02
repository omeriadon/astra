# 10-bookmarks-reading-list handoff

Task / selected optional scope: Bookmark organization and interchange; reading-list metadata, sync, and explicit local offline WebArchive snapshots.

Branch / worktree / baseline commit: `astra/roadmap/10-bookmarks-reading-list`; `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/10-bookmarks-reading-list`; baseline `a623746`.

Status: source complete. Primary Xcode build and runtime acceptance remain pending.

Commit(s): `51445d0` (`implement bookmarks and reading list`), plus the follow-up durability checkpoint. No push or merge.

Changed files and behavior:

- `astra/Models/Library/Bookmark.swift`: existing bookmark records now carry folder, favorite, and order metadata. Missing fields decode with safe defaults. A bounded migration helper assigns legacy flat-array order without advancing `modifiedAt`. Adds timestamped `ReadingListItem` metadata and a monotonic user-data mutation clock helper.
- `astra/UI/Content/BrowserBookmarksView.swift`: searchable grouped bookmarks, favorite marking, edit/move/reorder controls, and a separate reading-list view with read/unread, removal, and offline-copy actions. The edit sheet uses the existing List style, matched transition, accessibility identifiers, cancel role, and prominent confirm button.
- `astra/Storage/BrowserUserData.swift` and `astra/App/BrowserDataTransfer.swift`: current JSON interchange now includes reading-list metadata. Netscape HTML import/export preserves bookmark titles, URLs, folders, and ordering with HTML escaping. Import validates the whole document, including raw history URLs before credential stripping, before mutating browser state; duplicate URLs prompt through the shared serialized `BrowserWebsiteUI.present` path to keep, replace, or cancel. Executable, credential-bearing, file, and other non-HTTP(S) links fail the import. Import rechecks visible normal-window ownership after file decoding and the prompt. The native file panel owns each security-scoped grant, which is stopped once after I/O. The HTML reader bounds input and token counts, handles nested Netscape folders and named/decimal/hex entities, and removes comments before tokenizing.
- `astra/Models/Core/Browser.swift`: adds rename, folder/favorite/order updates, reading-list add/read/remove, explicit selected-page archive capture, and offline opening. Actual edits advance past existing record and tombstone timestamps; unchanged edits do not stamp. Archive callbacks verify the tab, controller, document, URL, and list-item ownership. Save/delete operations are serialized through the existing session persistence task; deletion and synchronized URL changes remove the local archive.
- `astra/Models/Core/BrowserSnapshot.swift` and `astra/Models/Core/BrowserSyncDocument.swift`: persist and merge timestamped reading-list deletion clocks and metadata. Older snapshots/documents default the added fields. Bookmark ordering participates in deterministic sync ordering. Portable reading-list projection strips URL credentials; archive envelopes are absent from sync documents and JSON/HTML exports.
- `astra/Storage/BrowserPersistence.swift`: optional reading-list state decodes as empty for older snapshots. Each offline WebArchive is one atomic binary property-list envelope containing its exact URL, payload, and generation UUID, under the existing Application Support directory. Limits are 32 MiB per archive, 50 archives, and 256 MiB total. Save/load/delete and cap accounting serialize through a process-wide lock shared by all BrowserPersistence instances. Atomic writes return generation IDs; post-write ownership validation removes only that generation if the tab, controller, document, selected URL, or list item changed while the write was queued. Private sessions cannot write them.
- `docs/astra-roadmap/checks-10-bookmarks-reading-list.swift`: runnable production-model, import, sync, migration, and local-cache checks, including URL-changing replacement, rejected replacement preservation, generation-safe stale cleanup, concurrent writes across two persistence instances, 50-item and 256 MiB cap behavior, bounded reads, and directory-enumeration error propagation.

Acceptance cases satisfied, with evidence:

- Legacy bookmark JSON without new fields decodes safely. The migration check retains array order and `.distantPast` freshness. Legacy sync JSON without order fields also retains its source array order after decoding.
- JSON and Netscape HTML preserve bookmark metadata supported by each format. The HTML check covers nested folder names, root items after folder closure, ampersand/tag/quote escaping, decimal/hex entities, and comment removal. Malformed mixed content and JavaScript/file URLs are rejected before import applies anything.
- Sync checks verify newer bookmark/read metadata wins over stale metadata, deletion clocks suppress stale reading-list records, newer records can restore the same ID, credential-bearing reading URLs are stripped from outbound projections, and local mutation dates advance beyond future record/tombstone clocks.
- The production persistence check verifies URL-changing atomic replacement, preservation after rejected replacement, generation-safe deletion, simultaneous cap enforcement through two persistence instances, count/size limits, and directory error propagation. A mismatched item URL cannot open bytes saved for the previous URL.
- Offline payloads are device-local. The source adds no archive field to persisted/sync/export DTOs; only URL/title/date/read state syncs.

Checks run, scheme/destination/workspace and results:

- `swiftc` compiled and ran `docs/astra-roadmap/checks-10-bookmarks-reading-list.swift` against production `Bookmark`, `BrowserVisit`, workspace/tab/snapshot/sync models, `BrowserUserData`, and `BrowserPersistence`; passed after the follow-up durability changes.
- `swiftc -frontend -parse` passed for every changed production Swift file, including `Browser.swift`, `BrowserDataTransfer.swift`, and the SwiftUI view.
- `git diff --check` passed.
- No Xcode MCP build ran in this worker. The primary owns the serialized Mac build. No app, hosted target, fixture website, keychain, real user data, or server was used.

Checks written but not executed: No hosted tests or app runtime cases were added or run.

Pending runtime/hardware/provider cases: Mac and iOS target builds; signed-app persistence behavior; WebKit archive capture/open behavior on both platforms; resource fidelity, authenticated-page handling, navigation during save/open, tab/window closure, and memory use while WebKit materializes an archive. Apple documents [`WKWebView.createWebArchiveData(completionHandler:)`](https://developer.apple.com/documentation/webkit/wkwebview/createwebarchivedata%28completionhandler%3A%29) as producing an archive of the current WebView contents; this does not establish complete offline reproduction of every page resource. The 32 MiB cap applies before disk write, after WebKit has returned `Data`, so transient capture memory is not bounded by the store.

Migration, compatibility and private-data impact: Persisted `readingList` is optional when decoding prior browser snapshots. `BrowserSnapshot.deletedReadingListAt` defaults to empty for old snapshots. Bookmark folder/favorite/order fields decode to flat-bookmark defaults; array order is migrated without changing record freshness. Sync remains document version 3 with additive optional reading-list fields. Normal reading-list metadata and deletion clocks sync; private windows and local archive envelopes do not. Explicit deletion removes the local archive and updates the backup snapshot through existing persistence behavior.

Capability gates / unresolved issues: The Xcode build must confirm the public WebKit API and SwiftUI sheet APIs against the project’s exact macOS/iOS deployment targets. Runtime acceptance must determine archive fidelity and whether the current WebKit capture behavior is useful for representative pages. No completeness guarantee is made. Provider behavior with additive sync metadata remains covered by the existing task29 provider gate.

Merge prerequisites / follow-up ownership: Primary source review and serialized Mac build are required. Keep the existing task29 timestamp, endpoint, cache, and local-only-data rules. No project file, shared roadmap progress, controller, settings, downloads, defaults, or server code changed.
