# Astra native automation architecture

## Build targets

Astra retains one macOS application process. browserApp and AppDelegate remain the sole application entry point; a duplicate browser app target would split WebKit state and restoration.

| Component | Target | Responsibility |
|---|---|---|
| Packages/AstraAutomationCore | SwiftPM library | Stable tab/window IDs, library deep links, bounded HTTP(S) URL validation. No AppKit, WebKit, or singletons. |
| astra/Automation/AstraSystemActions.swift | astra app | Main-actor bridge to existing Browser APIs; resolves windows after restoration. |
| astra/Automation/Intents/ | astra app | Shortcuts, Siri, Apple Intelligence schemas, and entity queries. |
| astra/Automation/Spotlight/ | astra app | Incremental non-private library metadata indexing. |
| astra/Automation/Services/ | astra app | Five NSServices accepting selected text or URLs. |
| astra/App/AppDelegate.swift | astra app | Register services, restore Spotlight deep links, refresh shortcut parameters. |
| AstraWebsiteAppRuntime | Separate existing runtime | Explicitly excludes ALL automation source files. |

The app target links the SwiftPM product; the website runtime does not.

An App Intents extension only executes in the background. UI-changing actions must live in the app process. A future background-only extension should share the Foundation-only package and use explicit App Group storage or IPC; it must not link live WebKit controllers.

## Invariants

- Intent entities are snapshots identified by UUID. A tab reference combines its window UUID and tab UUID.
- An action resolves its target at execution time, checks ownership and hydration, and rejects stale IDs.
- The browser model remains the only owner of mutable session state.
- A cold-start action must await window restoration instead of modifying placeholder tabs.
- No private browsing history, page bodies, window contents, or selected text enter Spotlight.
- Services reject script/file URLs and oversize text. App Intents and Services use shared validation.
- App Shortcuts are curated. The larger action catalogue is separately available in Shortcuts.

## Spotlight lifecycle

Only bookmarks, reading list and spaces are indexed. Updates are coalesced for 1.2 seconds. Stable SHA-256 fingerprints avoid reindexing unchanged records; removed IDs are deleted. Results use typed astra:// UUID links and are revalidated against live storage. Index domain: com.omeriadon.astra.library.

## macOS Services

Search Web with Astra (text), Open in Astra (URL), Open in Mini Astra (URL), Save in Astra Reading List (URL), Create Astra Easel from Selection (text or URL).

## Validation

Run these commands on macOS with Xcode 27:

- swift test --package-path Packages/AstraAutomationCore
- python3 checks/native-automation-check.py
- xcodebuild build -project astra.xcodeproj -scheme astra -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

Manual acceptance: cold launch from Shortcuts, every Service from another app, multiple normal/private windows, tab identity expiry, Spotlight add/rename/delete, hundreds of bookmarks, and Siri invocation in a signed app. Siri natural-language availability depends on the system configuration.

## Future boundaries

Move only reusable domain logic into AstraAutomationCore. Do not move AppKit windows, WebKit controllers, or shared browser singletons there. Build a background App Intents extension only if background-only operations with explicit shared persistence become necessary.
