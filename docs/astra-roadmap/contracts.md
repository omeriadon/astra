# Astra architecture contracts

This baseline records the existing attachment points for roadmap work. It does not add service interfaces.

| Responsibility | Existing owner | Contract for later packets |
| --- | --- | --- |
| Window and tab organization | `Browser`, `BrowserWorkspace`, `BrowserSpace`, `BrowserWindowRegistry` | Keep stable tab/space IDs and selection coherent after close, restore, sync, and transfer. Spaces organize tabs; they do not partition website data. |
| Web page lifetime | `BrowserTab`, `BrowserController`, `BrowserWebView` | One controller owns its web view and session. Capture best-effort restoration state before releasing a controller; fall back to its saved URL. Ignore callbacks from an old navigation/document. |
| Website data and privacy | `BrowserWebSession`, `BrowserSitePermissions` | Resolve website data, permission, favicon, download, and extension services from the tab's session. Normal windows share the default persistent store and shared services. Each private window owns a nonpersistent store, permission set, favicon store, and download manager. Private browsing does not write browser persistence or sync. |
| Durable browser state | `BrowserPersistence`, persisted model types, `BrowserRestorationStore` | Validate and atomically save the normal session. Preserve unreadable or future-version data. Keep native interaction-state blobs encrypted and bound to their URL; never persist them for private tabs or send them through sync. Clearing history must account for recoverable backup state. |
| Website prompts | `BrowserWebsiteUI`, `BrowserController`, `BrowserSitePermissions` | Present prompts through the owning window, serialize them per window, and complete/cancel once. Recheck document and window ownership before applying a response. Cancellation is not a stored denial. |
| Navigation and page actions | `BrowserController` and its WebKit delegates | Keep policy at the delegate boundary. Preserve original `URLRequest` and supplied popup configuration where headers, POST bodies, opener behavior, or WebKit state depend on them. Use public APIs; unsupported actions retain a native WebKit or URL fallback. |
| Browser chrome | Current shell, selected `BrowserTab.activeController` | Derive URL, title, progress, security, find, media, and capture state from the selected tab's active controller, including peeks. Do not report unsupported engine state as if it were observed. |
| Extensions | `BrowserExtensionManager` and `BrowserExtensionWindow` | Use public `WKWebExtension` hosting and declared permission prompts. Keep extension actions unavailable to private windows. Do not emulate unsupported Chrome APIs or native messaging. |
| OS and release integration | `AppDelegate`, `BrowserAuthenticationSessionHandler`, `UpdateManager`, project metadata | Keep macOS lifecycle, menus, URL/authentication launches, and update behavior in their current owners. Treat signed entitlements and runtime provider acceptance as separate release gates. |

## Protected behavior

- All normal windows and spaces continue to share the default WebKit website data and normal session services.
- Private windows remain independently isolated, nonpersistent sessions. Closing a private window clears its transient download, permission, and website data state; downloaded files already saved by the user remain on disk.
- WebKit and the OS own page rendering, JavaScript, website storage internals, networking, DNS, TLS validation, codecs, and media playback. Astra owns browser policy, native prompts, persistence, UI, and safe lifecycle decisions.
- Preserve the current non-destructive lifecycle behavior. Memory pressure drops preview snapshots; it does not prove that page capture is protected. Do not add destructive hibernation without a verified capture/draft protection path.
- Preserve source-specific public API and runtime gates. A compile result, Safari product behavior, WebKit upstream source, or private selector does not prove the embedded public API works for Astra.

## Roadmap attachment points

| Change area | Existing attachment point | Reserved packet(s) |
| --- | --- | --- |
| Lifecycle, navigation, permissions, media and page tools | `BrowserController` and existing WebKit delegates | 01, 02, 05, 06, 13, 16, 18, 20, 22, 24–27 |
| Persistence, sessions, private browsing and profiles | `Browser`, `BrowserWebSession`, `BrowserPersistence`, `BrowserDefaults` | 03, 04, 18, 28–30 |
| Window shell and OS events | `AppDelegate`, `BrowserWindowController`, `BrowserWindowRegistry` | 08, 17, 24a, 31–34 |
| Permission prompts and authentication | `BrowserWebsiteUI`, `BrowserAuthenticationSessionHandler` | 05, 13, 23 |
| Feature-specific UI | Existing settings, chrome, shell, and content views | Owning feature packet; final settings navigation belongs to 28 |
| Xcode project, scheme, entitlements and release metadata | Existing project and shared scheme | 00, 23, 27, 31–33 |

Reserve shared-file edits through the primary before a later packet changes an owner listed above. Extend an existing owner first; split responsibility only when an actual feature needs a distinct boundary.

## User-required sync/cache contract

Local device storage remains usable independently of account or network state. Restore cached settings and browser records before sync. Invalid endpoint, offline failure, token expiration and sign-out retain normal cached data. Remote application is saved locally, and failure to save remains visible.

Every synchronized record and ordering/selection/deletion scope carries a persisted last-update value. Existing `modifiedAt`/`favouritesModifiedAt` names serve that purpose; future bookmarks, history, spaces/folders, settings, reading-list/profile metadata or other synced additions must participate explicitly. Local mutations update their owning version. Decode, render, encode and restoration do not invent newer updates. Unknown legacy freshness uses a deterministic migration policy.

Incoming sync merges against the latest local state after every relevant await. Newer local records survive, including edits in another same-session window. Absence of a record is not deletion; timestamped tombstones and history-clear metadata control deletion. A missing tombstone never removes a record merely because its legacy timestamp is unknown. Tie resolution and ordering must converge deterministically. Private data, device credentials, endpoints, local files and restoration blobs remain outside portable payloads.

History is now explicitly included in the user-selected sync scope. Task 09 consumes this contract rather than returning to the earlier local-only history policy. Future feature tasks register portable settings and metadata with the sync/cache schema when adding them; per-device values remain local for a documented reason.
