# 27-internal-urls

Task / selected scope: Packet27. Preserve Astra native internal pages as first-class tab identities and define a strict internal `astra://` routing namespace without registering or exposing it to ordinary webpage navigation yet.

Branch / baseline: `astra/roadmap/27-internal-urls`; baseline `c8e71de1548d18038cb828d97387932346673cc1`.

Status: source implementation complete for routing policy/parser; Xcode compilation and eventual trusted caller wiring remain pending for the user's Mac/integration pass.

Commits: parser/router `f48373f805fd307be1f348ed60a5e8132255f0a0`; focused check `9368648e32fed9b7ac11fd719043d242b1733978`.

Existing native-page behavior reviewed:

- `BrowserInternalPage` keeps stable persistence IDs for theme editor, settings, history, bookmarks and DEBUG-only failure states. Unknown persistence IDs return nil.
- `BrowserContentView` renders internal destinations with native SwiftUI views; no privileged HTML page or script bridge is used.
- `Browser.openInternalPage` reuses an existing visible internal tab unless a new tab is requested, restricts private windows to the privacy settings page, and keeps internal tabs outside normal website history/sync tombstones.
- Browser search actions already point directly to the native internal-page APIs.

Added routing contract:

- `BrowserInternalURL` accepts only the exact `astra` scheme, no credentials, ports, fragments or extra paths, and rejects duplicate/unapproved query keys.
- Allowlisted destinations are `new-tab`, `settings`, `history`, `bookmarks`, `theme`, `extensions` and `version`. Extensions/version resolve to the existing native Settings subpages; settings has a bounded `page=` mapping.
- Routing carries an explicit source classification. Only `.userInterface` and `.operatingSystem` are trusted. `.webContent`, `.extensionContent` and `.importedData` always fail before destination parsing, so a webpage link, extension action, synced document or imported bookmark cannot mint internal privilege.
- Private windows cannot route to the theme editor and settings remain constrained to Privacy & Security by existing browser policy.
- `BrowserNavigationPolicy` already refuses `astra` and `astra-*` as external-application handoff schemes, so web navigation cannot escape through LaunchServices merely because a custom-looking scheme exists.

Deliberately not activated yet:

- `astra://` is not registered in Info.plist in this packet and is not automatically interpreted by generic web navigation. The parser is ready for a later trusted address-bar/OS integration point, but registration without a source-trust boundary would weaken the packet's security goal.
- Downloads remain existing native browser chrome/sidebar rather than a fake internal website. No synthetic downloads HTML route was added.
- DEBUG failure routes remain compile-time DEBUG only and are not encoded into the release allowlist.

Verification asset: `checks-27-internal-urls.swift` covers valid destinations, settings subpages, unknown/extra paths, duplicate query keys, privileged-looking query attempts, credentials, fragments, ports, wrong schemes and every untrusted source class. Execution remains for the user's local Swift/Xcode pass.

Data/privacy/migration impact: none. Existing internal persistence IDs are unchanged, so restored tabs retain compatibility. No internal URL is synced or treated as web history.

Merge prerequisites: packets02,03,17,20. Later packet31 may activate trusted OS integration after this policy is present. User-controlled integration only.
