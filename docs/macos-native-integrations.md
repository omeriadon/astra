# Astra macOS system integration

## Scope

Target: Astra macOS 27, `release/0.1+3`. Main browser target only;
the embedded website-app runtime excludes the new files. AppKit remains
the sole application/window lifecycle owner.

This implementation deliberately exposes a smaller tested API surface than the
total feature catalogue. Further intents should only be added with stable state
identity, authorization checks, useful parameters and no direct WebKit ownership.

## Implemented surfaces

### App Intents and Shortcuts

All registered intents are available as standalone actions in Shortcuts.
Ten high-value actions are curated as discoverable App Shortcuts with Siri phrases.

- Web navigation: open HTTP(S) URL, search with Astra's configured search engine,
  get current URL and title, load URL in an identified tab, back/forward, regular
  reload and reload from origin, reader mode, zoom in/out/reset, translation.
- Tabs: new, close selected/specific, duplicate, reopen closed, switch between
  specific owned tabs across windows, list, move between favourite/pinned/normal
  areas and spaces, hibernate, bookmark or add to reading list.
- Windows: open normal/private window, open Mini Astra. Private sessions are not
  published as searchable tab entities, nor mixed with normal windows.
- Spaces: list, switch, create, create named, rename.
- Bookmarks: add current page/URL, resolve/list/search bookmark entities,
  open a particular bookmark.
- Reading list: save current page/URL/tab, list/search, open and mark read/unread.
- Easels: create; macOS Services can create an easel from selected text or URL.
- Chrome: sidebar, top bar, AI sidebar, downloads view and settings/internal pages.
- Media: picture-in-picture where supported by the selected WebKit page.
- Downloads: list, pause and resume by stable ID (using Astra's download manager).

Apple's browser AppEntity schemas are used for bookmark, tab and reading list;
browser-intent schemas are used for bookmark URL and URL-in-tab. Other actions
are ordinary App Intents. Schema adoption does not guarantee any particular
Apple Intelligence utterance, language or device capability.

### Spotlight

Indexes non-private bookmarks, reading-list metadata and space names using
Core Spotlight. Uses stable identifiers and incremental de-duplication/deletion
after a 1.2-second coalescing interval. Clicking a result deep-links back into
Astra through NSUserActivity or the custom `astra://` URL scheme.

**Never index** private session data, private tabs, page content, active
credentials, user prompts, or full browsing history by default. No background
WebKit/page content extraction is performed.

### AppKit Services

Selected text or URL in another macOS app:

- Search Web with Astra
- Open in Astra
- Open in Mini Astra
- Save in Astra Reading List (valid HTTP(S) URL required)
- Create Astra Easel from Selection

`Info.plist/NSServices` registers system menu titles and pasteboard types.
`NSApp.servicesProvider` routes service requests to the same system action bridge.

### Lifecycle and consistency

`AppDelegate.awaitSystemActionsReady()` gates launch-time operations until
window restoration completes. Intents resolve normal browser windows via
`BrowserWindowRegistry` and stable tab IDs. A stale ID produces an error rather
than targeting the first matching tab of some other window. Opening a tab does
not bind work to a private window merely because it is frontmost.

The embedded website-app runtime must never register Astra's global
Services, Spotlight items or Shortcuts metadata.

## Further catalogue (not claimed implemented)

- More Apple's browser-intent schemas: multi-tab close, create-tab with return
  entity, find-on-page with hit results, multi-bookmark deletion, history clearing
  with confirmation, and window entities and close-window actions.
- Browser-wide history search intent with pagination and opt-in Spotlight index.
- Reader/translation result output into Shortcuts, PDF/screenshot as typed files,
  website AI summary and interactive AI prompting as asynchronous results.
- Page selection extraction, current-page source text, and advanced WebKit-specific
  features where API and privacy protections permit.
- Download cancellation/clear-list with explicit confirmation, and sharing/revealing
  completed files with sandbox permissions respected.
- Easel object insertion and targeted edit operations; boosts management after
  the underlying boost feature is merged into the target branch.
- Siri intent phrases that need device-side availability testing and full system
  browser schema adoption for Apple Intelligence.

## Required macOS validation

1. Use Xcode 27 and Swift toolchain configured for the main `astra` scheme,
   compile Debug and Release, check generated App Intents metadata.
2. Test all ten App Shortcuts in Shortcuts and Siri on an eligible Mac, including
   execution after a cold launch and when Astra has no normal window.
3. Open two normal windows and one private window. Switch specific tabs and
   verify action ownership never crosses normal/private boundaries.
4. Index bookmarks, reading list and spaces; edit/delete each and verify
   Spotlight updates, stale item removal and exact-deep-link destinations.
5. Select text and URLs in TextEdit, Finder, Safari and Mail, and verify Services
   actions and invalid-input error reporting. macOS may cache the Services list;
   relaunch and refresh Services registration if necessary.
6. Test downloads while paused, resumable, completing, inaccessible or stale.
7. Profile cold launch, add 2,000 bookmarks, switch spaces and monitor indexing:
   no WebKit creation on Spotlight refresh and no synchronous disk IO on the
   main actor.
8. Verify the embedded website-app runtime contains no Astra App Intents or
   NSServices registration.

**Validation status:** Source changes are committed; an Xcode/macOS build and
device-level Siri/Spotlight/Services execution cannot be run from the current
Linux-based tools. No compile or end-to-end test success is claimed.
