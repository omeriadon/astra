# 25 Page tools, context menus and drag handoff

Task / selected scope: `25-page-tools-context-drag`; native page exports with exact ownership, native page/selection sharing, safe URL copy, validated address-bar drops, and existing WebKit context-menu behavior.

Branch / worktree / baseline commit: `astra/roadmap/25-page-tools-context-drag` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/25-page-tools-context-drag` / `baselineea29d26`.

Status: source work complete for implemented paths; primary review and serialized Mac build required. Native context-menu augmentation and completed-download file drag remain capability/runtime gates.

Commit(s): `4b9cc5b` (`implement page export ownership and drops`); documentation checkpoint pending.

Changed files and behavior:

- `astra/Web/Navigation/BrowserDesktopCommands.swift` captures the exact selected Browser, tab ID, controller, WebView, committed URL, navigation generation and owner window before page export/share. Save-panel callbacks and asynchronous PDF/archive/source capture revalidate those owners before and after capture. A tab switch, navigation, controller replacement, window change or cancellation discards the result. The save-panel URL's system-granted security scope is balanced after capture/write. Export attribution strips URL user information.
- `astra/Web/Navigation/BrowserPageExportPolicy.swift` contains the production generation/document ownership decision and exclusive final-write helper. It atomically stages beside the selected destination, then uses an exclusive hard link so an existing file cannot be replaced by an export race. Quarantine failure removes only a destination created by this export.
- `astra/Web/Navigation/BrowserController.swift` exposes whether a committed page document remains current for page-tool ownership checks.
- `astra/App/AppDelegate.swift` adds the native Share Page command. It shares the selected page or current main-frame selection with the credential-stripped URL. The existing Copy URL command already strips URL user information.
- `astra/UI/Shell/DesktopBrowserShell.swift` accepts URL or text drops only over the visible macOS top bar. It validates through the existing `BrowserAddress.destination`, caps input at 8 KiB, permits only HTTP(S) destinations, and confirms the same selected tab/controller before navigation. It does not attach a drop handler to the WebView, preserving native page file-upload drops.
- WebKit's existing native page context menu remains the owner of native lookup/edit actions. No private menu selectors or custom DOM interception were added.
- `checks/task25-page-export-check.swift` exercises the production ownership policy and verifies exclusive writes preserve an existing file.

Acceptance evidence:

- Export writes require the same selected tab, controller, session, live WebView, committed URL, navigation generation and native window captured when the action began. The policy rejects changed generation, URL, WebView or window and rejects uncommitted/loading documents.
- Canceling the save panel returns before creating a task or file. Losing page ownership during asynchronous capture drops the output. Destination collisions fail without replacing existing content. Private/session state is not persisted by the export flow.
- URL copy, share URLs, and quarantine attribution remove URL user/password fields. User-selected page data is only exported/shared after an explicit native action.
- Top-bar drops reject malformed, oversized, credential-bearing, file and non-HTTP(S) values. Search text routes through the existing configured address destination. The page view itself keeps native WebKit upload/drop handling.
- PDF and WebArchive use WebKit's native capture APIs. HTML source is the current main-frame `document.documentElement.outerHTML`; linked-resource crawler and universal offline-replay claims were not added.

Checks run:

- `swiftc astra/Web/Navigation/BrowserPageExportPolicy.swift checks/task25-page-export-check.swift -o /tmp/task25-page-export-check && /tmp/task25-page-export-check` — passed: `Task 25 page export policy checks passed`.
- `swiftc -frontend -parse` over every task-touched production Swift file and the check source — passed. This checks syntax, not app target type checking.
- `git diff --check` — passed.
- No Xcode workspace was opened or built by this worker; the primary owns serialized Xcode verification. No app, browser fixture, hosted test, file panel, sharing provider, or download was run.

Pending runtime/API cases:

- Confirm WebKit WebArchive/PDF fidelity and native print behavior on macOS; test canceled/queued save panels, navigation or tab switch during capture, close during capture, filename types, exclusive collision behavior and quarantine in the signed sandbox.
- Exercise Share Page with a page, main-frame selection, credential-bearing URLs, canceled share panel and page/tab changes during selection capture.
- Exercise URL/text top-bar drops, malformed provider payloads, search text, hidden/revealed top bar, and confirm file drops over page content still reach WebKit upload controls.
- Apple documentation search returned public WKUIDelegate context-menu configuration and animator methods based on `UIContextMenuConfiguration` and `UIContextMenuInteractionCommitAnimating`; it did not surface a public AppKit API for appending items to WebKit's native `NSMenu`. Keep native WebKit menus, including native edit/lookup behavior, and do not emulate the DOM context menu or use private selectors. Link/image actions beyond WebKit's native menu remain subject to a public AppKit extension point.
- Completed-download drag-out is not implemented. A safe public path must keep each record's exact security-bookmark scope valid through the receiving app's deferred file-promise write and must preserve the actual completed file. Do not expose a raw bookmarked path or start a scope only while constructing a lazy provider. Use the existing manager access rules when this path is implemented.
- iOS-specific browser toolbar drag targets and native share acceptance were not changed; this branch limits custom URL/text drop behavior to the macOS top bar.

Migration, compatibility and privacy impact: no schema, Defaults, sync, project, entitlement, bookmark, download-record or user-data change. Page output is an explicit user-selected local write. No automatic export/recent item or custom offline snapshot is created. URL credentials are excluded from copy/share/quarantine attribution. No page content is placed in diagnostics or browser persistence.

Capability gates / unresolved issues: primary source review and a serialized Mac Xcode MCP build are required. Source parsing and the production helper check do not establish AppKit/WebKit target type checking, signed sandbox access, archive fidelity, share provider behavior, context-menu runtime behavior, or file-drag security scope lifetime. Download file drag and custom AppKit context augmentation remain open as above.

Merge prerequisites / follow-up ownership: primary review and Mac Xcode MCP build. Preserve task 10's native WebArchive reading/offline snapshot behavior, task 12's exclusive destination/quarantine/scoped-file conventions, task 13's native page upload drop behavior, task 16's selected find/zoom owner, task 17's focused menu target and task 23's authentication boundaries. No push, merge, project configuration edit, hosted test or app launch occurred.
