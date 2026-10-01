# Task 03 persistence and restoration handoff

Task / selected scope: 03 persistence and restoration; no optional scope selected.

Branch / worktree / baseline: `astra/roadmap/03-persistence-restoration`; `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/03-persistence-restoration`; combined baseline `358dd7dbcb988108a3cd1c7ad89decf33ab1f06`.

Status: implementation and source checks complete; runtime acceptance pending.

Commit: checkpoint `implement startup recovery and window persistence`.

Changed files and behavior:

- `BrowserPersistence.swift` writes snapshot envelope version 3, decodes older envelopes through their existing defaults, merges versioned device-local window records, tracks clean/unclean shutdown in a separate versioned sidecar, and rejects saves over a future-version primary.
- `Browser.swift` records unclean launch before hydration and clean termination after queued saves finish. Restore, blank, and homepage startup choices affect only the first normal browser window in a process. Blank/homepage preserve the cached session during startup; the first later full session mutation archives displaced open tabs as closed tabs before saving. Homepage URLs are limited to credential-free HTTP(S). Selection and workspace saved timestamps remain unchanged during restoration.
- `BrowserWindowRecord` version 1 stores window ID, ordered tab IDs, and selected tab ID. It contains no geometry and is not part of the portable sync document.
- `BrowserDefaults.swift` adds typed, portable startup and homepage keys to the existing settings sync registry. Their conflict timestamps use the existing settings-version tracking.
- `BrowserGeneralSettingsView.swift` exposes the startup choice and homepage URL in a Startup section.
- `AppDelegate.swift` records clean shutdown after persistence flush and the existing save-failure decision.
- `checks-03-persistence.swift` exercises version 3 writes, window record round-trip, corrupt-primary backup recovery, version 2 decoding, future-version preservation, and shutdown metadata transitions against production persistence code.

Restoration limits: saved URLs and back/forward history entries/index survive relaunch as browser-managed history; WebKit's live back-forward list is reconstructed and is not claimed to retain its internal entries. Scroll position is persisted and reapplied best effort. `WKWebView.interactionState` is encrypted locally and authenticated to the saved URL; missing Keychain data, URL mismatch, unreadable state, or WebKit rejection falls back to URL/history restoration. Form drafts, `sessionStorage`, and arbitrary page state are not promised. Private sessions remain outside normal persistence.

Checks:

- Xcode MCP opened `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/03-persistence-restoration/astra.xcodeproj`, workspace `workspace-VvsSm87feh`, scheme `astra`, destination `My Mac`; build succeeded.
- The first build exposed two invalid Swift if-expression branches; those were changed to ordinary statements, then the build passed.
- `swiftc` compiled and ran the standalone production persistence check successfully.
- No app launch or hosted tests were run.

Pending runtime cases: normal relaunch in each startup mode; crash/forced quit marker behavior; corrupt primary and backup combinations on disk; missing/lost Keychain key; restoration-state URL mismatch and WebKit rejection; tab ordering and selection after opening multiple windows; homepage navigation and repeated startup; save failure UI during actual quit. These require app/runtime or device interaction and remain unverified.

Migration and data impact: version 1/2 local envelopes remain readable; version 3 adds optional window records. Future envelopes cannot be overwritten through the persistence save API. Shutdown metadata is a separate version-1 local file, so older installs default to unknown shutdown state. Startup preferences join existing portable settings timestamps. Blank/homepage mode retains old tabs in the current cache until the next full mutation, then moves them to the recoverable closed-tab list. History, bookmarks, local file access data, encrypted restoration state, and sync freshness fields remain in the local saved snapshot. No new data is sent through sync.

Unresolved issues: Keychain-unavailable behavior and actual WebKit restoration quality are source-backed fallbacks only. The per-window record is a minimum versioned extension for task 08; it records tab ordering and selection but intentionally no window geometry.
