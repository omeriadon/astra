# Boosts

Boosts are user-authored CSS and JavaScript applied by Astra to ordinary HTTP(S) websites. They are **disabled in private browsing** and never injected into local `file:` documents.

## User interface

The macOS **Boosts** menu creates a Boost for the current website, creates a global Boost, or opens the library's Boosts category. The Library sidebar contains Downloads, Easels, and Boosts. Selecting the status control toggles a Boost. The adjacent edit control opens a standalone Boost editor; rows support context actions and swipe-to-delete.

The editor uses a native SwiftUI toolbar for the Boost's name, CSS/JavaScript picker, enabled switch, and all-sites/domain scope. The main content is a monospaced, syntax-coloured `NSTextView`. Source changes are saved after a short debounce, with JavaScript syntax validation through JavaScriptCore and lightweight CSS structural diagnostics. The token highlighter uses no external parser dependency.

## Matching and execution

- A global Boost matches every ordinary HTTP(S) page.
- A Boost scoped to `example.com` also matches `docs.example.com`, but never `notexample.com`.
- CSS is applied at document start, replaced in the current document when edited, and removed when disabled/deleted.
- JavaScript is injected as its own native WebKit user script at document end. Updated source is hot-swapped into already open pages, without using `eval()`, and unchanged source is not re-run on every CSS keystroke.
- No reload is required to add or edit source. Disabling JavaScript stops future injections but **cannot undo arbitrary side effects** of code that already ran. Code that modifies page state may therefore require a manual reload to reverse.
- Injection is main-frame only.

**Security:** Boost JavaScript executes in the website's page world, not a privileged Astra bridge. Enabling unfamiliar JavaScript may expose the contents of matching websites to that script; only enable code from sources you trust.

## Persistence and synchronization

The observable Boost store is shared across browser windows and saved separately from the full browser session. Its records and timestamped deletion tombstones participate in the existing `BrowserSyncDocument` merge, including portable projection and backward-compatible decoding when older snapshots contain no Boost fields. Updates use deterministic last-writer-wins conflict resolution. The store restricts the library to 512 Boosts, up to 128 KiB per CSS or JavaScript field, and a combined source/metadata budget of 1 MB to avoid exhausting the sync server's request allowance.

## Validation

- `swiftc -swift-version 6 astra/Models/Library/BrowserBoost.swift checks/boosts-model-check.swift -o /tmp/astra-boost-check && /tmp/astra-boost-check`
- `node checks/boosts-runtime-check.mjs`
- Run `checks/boosts-sync-check.swift` in the Xcode context of `BrowserSyncDocument.swift`.
- Build both the Astra macOS target and `AstraWebsiteAppRuntime` with Xcode 27.

The repository's Swift-model and WebKit check workflows invoke the first two checks.
