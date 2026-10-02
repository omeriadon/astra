# 17 Keyboard and menus handoff

Task / selected optional scope: `17-keyboard-menus`; baseline menus, keyboard routing, focused targets, dynamic Navigation/Bookmarks/Window menus, Downloads shortcut, and public Safari Web Inspector access preference.

Branch / worktree / baseline commit: `astra/roadmap/17-keyboard-menus` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/17-keyboard-menus` / `6bea35469d6d2444aa7e0d9c3fe1cb1e051b1c02`.

Status: source complete; Mac build pending primary serialized Xcode MCP verification; native keyboard/menu and Safari inspection runtime acceptance pending.

Commit(s), or explicit uncommitted state: `8d069ce` (`implement focused keyboard menus`).

Changed files and behavior:

- `astra/App/AppDelegate.swift` resolves the browser only when `NSApp.keyWindow` belongs to a registered Browser or Mini Astra window. Authentication session state and registry fallbacks no longer redirect commands to another browser. Page-bound actions disable without a focused browser and check page/navigation/zoom availability. `closeTab` now closes the focused tab or Mini Astra window, not an unrelated key window while an authentication session exists. History and bookmarks menus rebuild on open from live visit/bookmark IDs; private bookmark entries are omitted. The Window menu rebuilds from live window IDs and labels only normal/private/Mini Astra window kind, not page titles. Downloads uses Option-Command-L and sends an owner-window-scoped request to the existing downloads sidebar state.
- `astra/UI/Tabs/ControlTabSwitcher.swift` uses the existing `WindowFocusReader` host window and only handles its key window. Command/Option combinations pass through, including VoiceOver Control-Option-Tab and Control-Command-Tab. Control-Tab and Control-Shift-Tab retain tab switching.
- `astra/UI/Content/BrowserRootView.swift` passes its existing native host-window reference into the switcher.
- `astra/UI/Shell/DesktopBrowserShell.swift` handles Downloads requests only for its matching Browser window while that window is key.
- `astra/Storage/BrowserDefaults.swift` and `astra/UI/Settings/Detail/BrowserGeneralSettingsView.swift` add a local, opt-in Web Inspector preference. It applies to pages when their WebViews are created and explains Safari Develop-menu hosting.
- `astra/Web/Navigation/BrowserController.swift` uses public `WKWebView.isInspectable` with the preference and removes private developer-extras and inspector-attachment selectors.

Acceptance evidence:

- Menu targeting maps the actual native key window to the existing app-owned normal/private/Mini Astra controller arrays. A non-browser key window produces no browser target. Menu entries store UUIDs and resolve them against the current active browser/window when invoked.
- History is limited to the current focused Browser's latest ten committed visits. Bookmark entries are omitted for private windows and looked up against the current browser on invocation. Window entries expose no page URL or title.
- Downloads requests include the originating Browser window UUID; only the matching key-window DesktopBrowserShell opens its existing sidebar.
- The switcher monitor is gated by the bridged native key window. Only Control-Tab and Control-Shift-Tab are intercepted; Control-Option and Control-Command combinations pass through. Escape cancellation and Control-release commit behavior remain.
- Standard Edit actions retain nil targets for AppKit responder-chain dispatch. Browser page shortcuts do not assign Edit actions such as copy/cut/paste/select-all.
- No `_inspector`, `_setInspectorAttachmentView:`, or `developerExtrasEnabled` use remains in AppDelegate/BrowserController. There is no in-app embedded inspector or inspect-element command because the current public API provides no command to host one; enabled pages are inspectable through Safari's Develop menu.

Checks run:

- `git diff --check` — passed.
- `swiftc -frontend -parse` on all seven changed production Swift files — passed. This is syntax parsing only, not target type checking.
- Source audit with `rg` for `_inspector`, `_setInspectorAttachmentView`, `developerExtrasEnabled`, and the removed toggle command — no matches in the scoped AppDelegate/BrowserController files.
- No Xcode MCP build was run; the primary owns serialized Xcode checks. No app was launched or operated. No hosted tests, formatter, or `xcodebuild` was run.

Pending runtime cases: keyboard focus across normal/private/Mini Astra and non-browser app windows; Control-Tab preview/cancel/release, VoiceOver shortcuts, IME and webpage form input; menu enabled state across blank/internal/loading/hibernated/failed pages and active peeks; stale menu invocation after focus/tab/window changes; history/bookmark privacy; Downloads shortcut/sidebar focus; Safari Develop-menu discovery on supported macOS versions and pages created before/after preference changes.

Migration, compatibility and private-data impact: adds one local Defaults Boolean, `webInspectorEnabled`, default false; it is not added to portable sync. History entries are transient menu IDs built from the currently focused Browser's existing visit records; private history remains in the private Browser's in-memory state. Window menu labels reveal only window kind, with no page content.

Capability gates / unresolved issues: WebKit exposes public inspectability through `WKWebView.isInspectable`, but Astra has no public embedded inspector-open or inspect-element API. Safari's Develop menu is the only advertised host. The setting applies when each page's WebView is created. Runtime confirmation of Safari discovery and support-version behavior remains open.

Merge prerequisites / follow-up ownership: primary source review and serialized Mac Xcode MCP build. No push, merge, project-file edit, private API expansion, hosted check, or app launch occurred.
