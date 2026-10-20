# Unsafe cleanup audit — build 3

Baseline: `adce2697479505a3ab51e3cf49b6b966bf5252bc` (`release/0.1+3`).

## Changes

- Watchdog/bootstrap state now belongs to one `Mutex`; timer creation/configuration/resume stays inside its critical section. No timer or mutable state escapes it. Logging and main-queue submission stay outside it.
- Download progress timestamps use `Mutex<[String: Date]>`; the same 100 ms wall-clock threshold, task-description keys, completion/error cleanup and pre-MainActor throttling remain.
- One persistence `Mutex<JournalState>` replaces the process-wide journal lock and owns revision ordering plus the bounded NSCache. All five existing transaction regions retain their extent, including disk writes, schema/privacy checks and journal merges. No nested acquisition was added. Cache count/cost limits, signature invalidation and commit ordering remain. The immutable persistence instance now has checked `Sendable` conformance.
- The website preparation registration probe uses a mutex; count/status reads and register increments are synchronized without escaping the stored state.
- Both SHA-256 formatters use native radix-16 conversion with a leading zero for bytes below 16.
- Decimal logging callers use `BrowserLog.fixedDecimal(Double, places:)`. Its closed precision enum and fixed `%.*f` format constrain the C argument contract. A single unsafe Foundation boundary is deliberately retained to preserve nil-locale printf semantics, rounding, negative zero, nonfinite spelling and arbitrary finite magnitudes. This is containment, not a claim that printf became memory-safe. No FormatStyle substitution is assumed equivalent.

## Remaining occurrences

The inventory below covers every remaining whole-word `unsafe` in executable-source/test files, including vendored keyword strings. Line numbers describe this revision. SwiftUI candidates are explicitly deferred rather than claimed necessary: removing them requires compiler acceptance with Xcode 27 / Swift 6.4. AppKit window, superview, responder, text-storage and delegate accesses acknowledge SDK lifetime annotations; adding a strong cache or tracking replacement could change window/view ownership and behaviour. Existing annotations remain unless an equivalent has been verified. Ordinary Foundation calls below expose pointer overloads even when nil is passed; existing dynamic validation/decoding was preserved.

No `nonisolated(unsafe)` declarations remain in first-party Swift or generated fixtures. No strict-safety settings were relaxed. No new unchecked Sendable/preconcurrency/import suppression was added. Private WebKit Inspector implementation files and vendored packages are unchanged.

| File | Lines | Retention rationale |
| --- | --- | --- |
| `AstraWebsiteAppInstaller/AstraWebsiteAppInstallerApp.swift` | 148, 189, 192 | Security out-parameter; no-follow quarantine removal; C error-string lifetime. Signing and path checks unchanged. |
| `AstraWebsiteAppLoader/BrowserWebsiteAppLoaderMain.swift` | 13, 16, 17, 21, 38, 52 | Verified runtime loading, symbol lookup/function-pointer conversion and Security out-parameters. |
| `Packages/MarkdownView/Sources/MarkdownView/Components/CodeView/Syntax/SyntaxLanguage+Catalog.swift` | 91, 157 | Syntax-highlighting keyword strings; vendored code unchanged. |
| `astra/AI/BrowserAIAttachment.swift` | 96 | NSAttributedString documentAttributes pointer overload. Preserve document decoding. |
| `astra/AI/BrowserAICLI.swift` | 448, 478 | POSIX passwd pointer and C string; FileManager isDirectory out-parameter. |
| `astra/AI/BrowserAICommandInput.swift` | 60, 64, 75 | Scoped byte-buffer writes and poll descriptor pointer; preserve partial-write/backpressure handling. |
| `astra/AI/BrowserWebsiteAugment.swift` | 213 | CSP unsafe-inline string; changing it would change styling policy. |
| `astra/Agent/BrowserAgentImageEncoder.swift` | 35, 56 | CoreGraphics bitmap allocation pointer API with nil data. |
| `astra/Agent/BrowserAgentInputService.swift` | 25, 73, 77 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/Agent/BrowserAgentPageService.swift` | 249 | AppKit proposed-rectangle pointer API; preserve image representation choice. |
| `astra/Agent/BrowserAgentServer.swift` | 87 | Security random-byte buffer; preserve cryptographic credential generation. |
| `astra/Agent/BrowserAgentTestBootstrap.swift` | 99, 109, 112, 116 | POSIX unlink/open/write and scoped buffers; retain exclusive no-follow creation and 0600 permissions. |
| `astra/Agent/BrowserAgentUploadScopes.swift` | 30 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/App/AppDelegate.swift` | 97, 271 | SDK responder-lifetime reads nested in keyboard policy/readiness metadata; no safe SDK-verified equivalent established. |
| `astra/App/BrowserLog.swift` | 121, 225, 230 | One typed fixed-format C-varargs boundary plus OSLog static-string signpost interoperability. |
| `astra/App/BrowserResources.swift` | 17, 18, 19, 20 | Dynamic image lookup, Dl_info pointers and image-path C string. |
| `astra/App/BrowserWebsiteAppFileWorker.swift` | 147, 323, 328, 330, 345, 372, 378 | Trash result pointer, Security signing out-parameters and CoreGraphics bitmap API. Preserve validation/signature requirements. |
| `astra/App/BrowserWebsiteAppMenuIntegration.swift` | 88 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/App/MiniAstraShortcut.swift` | 17, 18, 19, 22, 24, 34 | Carbon opaque event/hotkey handles and registration callbacks. |
| `astra/App/UpdateManager.swift` | 16, 17, 18, 20, 21, 22, 24, 117, 118, 123, 127, 128 | Dynamic runtime handle/symbol ownership and C function-pointer conversion; preserve unload order. |
| `astra/Automation/Services/AstraServicesProvider.swift` | 29, 43, 57, 71, 85 | AppKit service error out-parameters supplied by the caller. |
| `astra/Models/Core/Browser.swift` | 2216, 2766, 2775, 2871, 2880 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/Models/Core/BrowserHibernationManager.swift` | 186 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/Models/Core/BrowserSyncDocument.swift` | 620 | Property-list format out-parameter overload (nil); preserve dynamic validation/casting semantics. |
| `astra/Models/Search/BrowserSearchMatching.swift` | 76 | Foundation XMLParser delegate SDK lifetime annotation; keep delegate ownership and parse behaviour. |
| `astra/Models/Tabs/BrowserTab.swift` | 474 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/Storage/BrowserProfileImporter.swift` | 109, 110, 111, 113, 166, 191, 192, 193, 194, 195, 196, 324, 329, 330, 331, 332, 336, 337, 340, 341, 343, 345, 349, 350, 352 | SQLite handles, columns, C strings and callbacks; property-list format pointer overload. Preserve readonly/limit/finalize behaviour. |
| `astra/Storage/BrowserRestorationStore.swift` | 61, 73, 82 | Keychain out-parameters and scoped symmetric-key bytes. Preserve key generation and protection. |
| `astra/Storage/BrowserSessionStore.swift` | 15 | Keychain result out-parameter; preserve accessibility/protection policy. |
| `astra/Storage/BrowserSync.swift` | 494 | Property-list format out-parameter overload (nil); preserve dynamic decoding. |
| `astra/Storage/FaviconStore.swift` | 314 | CoreGraphics bitmap pointer API with nil data. |
| `astra/UI/Chrome/BrowserAIChatSidebar.swift` | 410, 424, 495, 514 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/UI/Chrome/BrowserAnimationEligibility.swift` | 75 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/UI/Chrome/LibrarySidebarView.swift` | 294 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/UI/Content/BrowserBoostEditorView.swift` | 267, 314 | AppKit textContainer/textStorage SDK lifetime accesses; preserve native editing ownership. |
| `astra/UI/Content/BrowserPageView.swift` | 111 | Existing SwiftUI AnyTransition expression. No compiler available to establish a genuinely safe equivalent; deliberately deferred, animation unchanged. |
| `astra/UI/Content/EaselPointerModifiers.swift` | 26, 28 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/UI/Content/EaselTextEditor.swift` | 23, 24, 58, 60 | AppKit textContainer/window SDK lifetime accesses; preserve editing and focus behaviour. |
| `astra/UI/Content/NewTabView.swift` | 581, 635, 661, 755 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/UI/Content/WebsiteAugmentEditingOverlay.swift` | 127, 139 | SDK window lifetime access and AppKit proposed-rectangle pointer API; preserve scale/pixels. |
| `astra/UI/Peeks/PeekStackView.swift` | 129, 133 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/UI/Settings/Detail/BrowserWebsiteAppsSettingsView.swift` | 161 | AppKit bitmapDataPlanes pointer initializer (nil); preserve icon rasterization. |
| `astra/UI/Settings/Theme/BrowserThemeEditorView.swift` | 205 | Existing combined AnyTransition expression. No compiler available to verify replacement; deliberately deferred, animation unchanged. |
| `astra/UI/Settings/Theme/SVFieldRenderer.swift` | 40 | CoreGraphics image pointer API; preserve colour field rendering. |
| `astra/UI/Shell/BrowserSpacePager.swift` | 714, 738, 776, 840, 874, 884 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/UI/Shell/NativeSidebar/BrowserSidebarScrollView.swift` | 183, 185 | AppKit insertion-index/operation out-pointers; preserve native drop proposal. |
| `astra/UI/Tabs/BrowserTabDragCoordinator.swift` | 160 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/UI/Tabs/BrowserTabRow.swift` | 679, 682, 694, 700 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/UI/Tabs/BrowserWindowFrameReader.swift` | 41, 62 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/UI/Windowing/NonDraggableTitlebarRegion.swift` | 39 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/UI/Windowing/WindowDragBackground.swift` | 22 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/UI/Windowing/WindowFocusReader.swift` | 35 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/Web/Downloads/BrowserDownloadFileWorker.swift` | 68, 187 | FileManager isDirectory/resultingItemURL pointer overloads; preserve symlink and trash semantics. |
| `astra/Web/Downloads/BrowserDownloadManager.swift` | 134, 337, 340 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/Web/Extensions/SafariExtensionCandidate.swift` | 19 | Property-list format pointer overload (nil); preserve dynamic extension metadata decoding. |
| `astra/Web/Navigation/BrowserController.swift` | 290, 1237, 1557, 1682, 1692, 1695, 1714, 2712, 2716, 2743, 3820, 3968 | SDK window/event lifetime accesses and colour-component out-pointers. No substitute compiled against the required SDK. |
| `astra/Web/Navigation/BrowserDesktopCommands.swift` | 21, 52, 55, 68, 86, 90, 96, 97, 98, 120, 125 | Private Inspector perform/dlsym/WKInspectorAttach integration explicitly frozen; window lifetime reads and print modal pointer API retained. |
| `astra/Web/Navigation/BrowserNavigationFailure.swift` | 112, 117 | CFNetwork retained proxy-settings/proxy-list objects; preserve proxy diagnosis and ownership. |
| `astra/Web/Navigation/BrowserPageExportPolicy.swift` | 28 | POSIX hard-link primitive for exclusive, non-overwriting publication; preserve atomic/security semantics. |
| `astra/Web/Navigation/BrowserProcessMemory.swift` | 94, 95, 104, 110 | Darwin process-info out-buffers and raw pointer rebinding required by those C APIs. |
| `astra/Web/Navigation/BrowserScreenshot.swift` | 42 | AppKit bitmapDataPlanes pointer initializer (nil); preserve screenshot pixels. |
| `astra/Web/Navigation/BrowserSitePreferenceModel.swift` | 18, 20, 21, 180, 188 | IPv6 C address/buffer conversion and property-list format pointer overloads; preserve canonicalization and existing decode semantics. |
| `astra/Web/Navigation/BrowserWebPushManager.swift` | 6, 68 | Existing @unsafe UserNotifications import and SDK window lifetime access. Import safety needs SDK-level verification; notification behaviour unchanged. |
| `astra/Web/Navigation/BrowserWebView.swift` | 290, 315, 329, 354, 376, 418, 486, 487, 503 | SDK window/superview/event lifetime accesses plus private Inspector perform. Inspector integration untouched. |
| `astra/Web/Navigation/BrowserWebsiteUI.swift` | 84, 163, 181, 205, 228, 242, 362 | AppKit window/superview/event SDK lifetime access. Preserve hierarchy identity, focus and event routing; no SDK-compiled safe equivalent established. |
| `astra/Web/Reader/BrowserReaderScript.swift` | 67 | CSP unsafe-inline string needed by existing reader styles. |
| `checks/download-file-worker-check.swift` | 58, 65 | Adversarial fixture filename; no Swift unsafe expression. |
| `checks/easel-document-check.swift` | 31 | Adversarial fixture URL path; no Swift unsafe expression. |
| `checks/easel-sync-check.swift` | 24, 25, 26 | Fixture variable name for invalid sync payload; no Swift unsafe expression. |
| `checks/unsafe-cleanup-check.py` | 44, 50, 82 | Generated Swift test oracle intentionally calls original printf formatter to detect byte-for-byte changes; not production functionality. |

## Verification

Executed locally on Linux:

- `git diff --check`: passed.
- `python3 checks/compiler-safety-settings-check.py --skip-toolchain-check`: passed (settings only).
- `python3 checks/ci-toolchain-workflows-check.py`: passed.
- Python compilation of the changed/new fixture generators: passed.
- `check_registration_boundary()` from website-app preparation: passed.

Attempted, blocked by missing platform tools:

- Debug and Release `xcodebuild build` with the existing astra scheme/configurations: no xcodebuild.
- `bash checks/run-sync-models.sh`: no Swift compiler.
- `python3 checks/unsafe-cleanup-check.py`: no xcrun.
- Full website-app preparation: no codesign.
- Full compiler/toolchain check: no xcrun.

The macOS build workflow now requests both Debug and Release configurations. Existing PR CI also supplies sync/persistence integration, website-app preparation, download worker and compiler configuration verification; the separate Release archive workflow remains unchanged. The download workflow additionally runs the new production-extracted throttle/bootstrap stress and printf/hex equivalence check in Onone, O, and Thread Sanitizer modes. The persistence fixture adds parallel commits across instances plus failure/retry unlock coverage.

These Swift tests are added, not locally passed. Runtime race/deadlock, pixel/animation and performance regressions have not been ruled out by execution on this host; macOS CI and interactive validation remain required. The refactor preserves the existing transaction boundaries, task hops, timer cadence, cache policy and UI source.
