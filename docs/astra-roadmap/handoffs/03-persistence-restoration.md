# Task 03 persistence and restoration handoff

Task / selected scope: 03 persistence and restoration; no optional scope selected.

Branch / worktree / baseline: `astra/roadmap/03-persistence-restoration`; `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/03-persistence-restoration`; combined baseline `358dd7dbcb988108a3cd1c7ad89decf33ab1f06`.

Status: implementation and source checks complete; runtime acceptance pending.

Commits: `5992248` (`implement startup recovery and window persistence`), followed by the bounded primary-review correction checkpoint.

Changed files and behavior:

- `BrowserPersistence.swift` writes snapshot envelope version 3, decodes older envelopes through their existing defaults, merges versioned device-local window records, tracks clean/unclean shutdown in a separate versioned sidecar, and rejects saves over a future-version primary.
- `Browser.swift` records unclean launch once per normal process session and clean termination after queued saves finish. Restore, blank, and homepage startup choices affect only the first normal browser window in a process. Blank/homepage retain all loaded tabs and workspace organization, then select a new blank or homepage tab in that model. Homepage URLs are limited to credential-free HTTP(S), whitespace-free hosts, and ports in 1–65535. Existing selection and workspace freshness timestamps remain unchanged during restoration.
- `BrowserWindowRecord` version 1 stores window ID, ordered tab IDs, and selected tab ID. It contains no geometry and is not part of the portable sync document.
- `BrowserDefaults.swift` adds typed, portable startup and homepage keys to the existing settings sync registry. Their conflict timestamps use the existing settings-version tracking.
- `BrowserGeneralSettingsView.swift` exposes the startup choice and homepage URL in a Startup section.
- `AppDelegate.swift` records clean shutdown after persistence flush and the existing save-failure decision.
- `checks-03-persistence.swift` exercises version 3 writes, window record round-trip, duplicate/future window-record rejection, corrupt-primary backup recovery, version 2 decoding, future-version preservation, shutdown metadata transitions, and homepage validation against production helpers.

Restoration limits: saved URLs and back/forward history entries/index survive relaunch as browser-managed history; WebKit's live back-forward list is reconstructed and is not claimed to retain its internal entries. Scroll position is persisted and reapplied best effort. `WKWebView.interactionState` is encrypted locally and authenticated to the saved URL; missing Keychain data, URL mismatch, unreadable state, or WebKit rejection falls back to URL/history restoration. Form drafts, `sessionStorage`, and arbitrary page state are not promised. Private sessions remain outside normal persistence.

Checks:

- Xcode MCP opened `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/03-persistence-restoration/astra.xcodeproj`, workspace `workspace-VvsSm87feh`, scheme `astra`, destination `My Mac`. The initial build passed. After the review correction, a build request stopped before compilation because Xcode reported missing package products `Defaults`, `DockProgress`, `MaterialView`, `Noise`, and `Sparkle`.
- Xcode diagnostics reported no issues in `Browser.swift`, `BrowserPersistence.swift`, or `BrowserGeneralSettingsView.swift` after the correction.
- `swiftc` compiled and ran the standalone production persistence and homepage check successfully after the correction.
- No app launch or hosted tests were run.

Pending runtime cases: normal relaunch in each startup mode; crash/forced quit marker behavior; corrupt primary and backup combinations on disk; missing/lost Keychain key; restoration-state URL mismatch and WebKit rejection; tab ordering and selection after opening multiple windows; homepage navigation and repeated startup; save failure UI during actual quit. These require app/runtime or device interaction and remain unverified.

Migration and data impact: version 1/2 local envelopes remain readable; version 3 adds optional window records. Future envelopes and future window-record versions cannot be overwritten through the persistence save API. Duplicate/invalid window records produce a persistence error instead of trapping during merge. Shutdown metadata is a separate version-1 local file, read and marked unclean once per normal process session; older installs default to unknown shutdown state. Startup preferences join existing portable settings timestamps. Blank/homepage mode preserves the loaded tabs, workspace, history, bookmarks, file access data, restoration state, and sync freshness fields while opening an additional selected tab. No new data is sent through sync.

Unresolved issues: Keychain-unavailable behavior and actual WebKit restoration quality are source-backed fallbacks only. The per-window record is a minimum versioned extension for task 08; it records tab ordering and selection but intentionally no window geometry.
