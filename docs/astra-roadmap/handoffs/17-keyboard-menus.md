# 17 Keyboard and menus handoff

Task / selected optional scope: `17-keyboard-menus`; native focused command routing, application menus, dynamic history/bookmark/window entries, Downloads, public Safari Web Inspector access, and explicit address-bar external-app prompt ownership.

Branch / worktree / baseline commit: `astra/roadmap/17-keyboard-menus` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/17-keyboard-menus` / `6bea35469d6d2444aa7e0d9c3fe1cb1e051b1c02`.

Status: source complete; Mac Xcode MCP build pending primary serialization; native keyboard/menu, external prompt, and Safari Develop runtime acceptance pending.

Commit(s): `8d069ce` (`implement focused keyboard menus`), `ca00469` (`record keyboard menus handoff`), `bf6d6c0` (`correct keyboard menu ownership`), `b4ce76c` (`preserve focused auth menu behavior`), `60331bc` (`add owned offline archive navigation`, prerequisite helper supplied by packet 10), `22931e5` (`fix offline archive navigation state`, isolated archive-state correction checkpoint for packet 10), and `3d96655` (`scope external address prompts to focused browser`).

Changed files and behavior:

- `astra/App/AppDelegate.swift` resolves active authentication sessions through their native key window, then resolves normal/private/Mini Astra windows by actual key-window identity. Page commands use the selected tab's active controller. A non-browser key window does not fall back to a different browser. New Tab from an authentication session opens a normal window; Cmd-W closes the authentication window and cancels its native session. Back/forward/reload/find/page actions continue to target the focused authentication browser where applicable. Settings reuses the focused normal/private window or creates a normal settings browser when there is no such target.
- Navigation, Bookmarks, and Window menus keep their stable items and shortcuts installed from launch. On menu open they refresh only dynamic entries: the current browser's recent visit IDs, non-private bookmark IDs, and live window IDs. Private bookmark entries are hidden, history entries are session-local, and window labels disclose no page title or URL.
- Option-Command-L opens Downloads in the existing sidebar. Its notification carries the owning browser window ID and only the matching focused `DesktopBrowserShell` handles it.
- `astra/App/BrowserKeyboardMenuPolicy.swift` owns production decisions for key-window matching, Control-Tab interception, menu availability, and explicit address prompt ownership. `checks/task17-keyboard-menu-policy-check.swift` exercises these same production rules without creating windows or launching Astra.
- `astra/UI/Content/BrowserRootView.swift` passes its existing native window bridge to `astra/UI/Tabs/ControlTabSwitcher.swift`. The switcher only handles that key window and preserves Control-Option-Tab, Control-Command-Tab, and marked-text input. Authentication Browser windows do not install the tab switcher; regular Mini Astra uses its separate view.
- `astra/Web/Navigation/BrowserController.swift`, `astra/UI/AddressBar/BrowserAddressField.swift`, and `astra/Models/Search/BrowserSearch.swift` distinguish actual address submissions from other URL loads. Only the address field and typed new-tab search use `loadFromAddressBar`; bookmarks, history, suggestions, OS URLs, extensions, and page-originated links keep their existing prompt ownership. On macOS, explicit prompts require the current focused Browser, selected active controller, same session, same live WebView, same navigation generation, and matching owner window. That owner is captured for the alert and revalidated while the alert is queued/presented and after it completes. Website-origin requests still use the existing `ownsPrompt` path.
- `astra/Web/Navigation/BrowserController.swift` also applies the inspector preference to already-created controllers through the existing UserDefaults change notification pattern. Normal tabs, peeks, authentication Browser pages, and Mini Astra controllers update without rebuilding their WebViews.
- `astra/Storage/BrowserDefaults.swift` and `astra/UI/Settings/Detail/BrowserGeneralSettingsView.swift` add the local, opt-in Web Inspector setting. It defaults false and applies through public `WKWebView.isInspectable`; Safari's Develop menu is the advertised host. No embedded inspector-open or inspect-element command is exposed.
- The packet 10 `loadWebArchive` helper checkpoint was included to correct its navigation ownership: it clears pending requests before lazy WebView creation, marks navigation pending, invalidates find state, rejects stale callbacks, and records a native-load failure. The isolated correction commit is `22931e5` for packet 10 to copy back.

Acceptance evidence:

- The exact key-window resolver is shared by AppDelegate and ControlTabSwitcher. Authentication sessions use their existing native-window resolver. Normal, private, Mini Astra, and auth focus do not use a stale registry fallback for menu targets.
- History menu IDs are resolved against the current browser's visit records. Bookmark IDs are resolved against the current non-private browser. Window IDs are resolved against the current AppDelegate controller arrays. Stale entries no-op or disable after focus/close changes.
- Cmd+W on an auth browser performs native window close. Cmd+T does not add a tab to its ephemeral Browser; it opens a normal Browser window. Internal history/bookmark/theme actions and data transfer are disabled for auth sessions.
- Stable shortcuts exist before each menu is opened. Dynamic items are inserted/removed by task-specific tags without deleting the stable command items.
- The Control-Tab policy check covers focused/unfocused targets, Control-Tab and Control-Shift-Tab, VoiceOver/Command modifiers, and marked text. Menu checks cover URL-copy presence, zoom bounds/reset, reopenable-tab state, and each explicit address ownership condition (focus, selected controller, session, WebView, navigation generation, and owner window).
- External address prompt ownership captures and rechecks the exact active selected controller and original native owner window. The site-origin branch remains unchanged and does not use the address-bar fallback.
- No `_inspector`, `_setInspectorAttachmentView:`, or `developerExtrasEnabled` use remains under `astra/`.

Checks run:

- `git diff --check` — passed.
- `swiftc -frontend -parse` over all changed Swift source files and the task check — passed.
- `swiftc astra/Web/Navigation/BrowserZoomPolicy.swift astra/App/BrowserKeyboardMenuPolicy.swift checks/task17-keyboard-menu-policy-check.swift -o /tmp/task17-keyboard-menu-policy-check && /tmp/task17-keyboard-menu-policy-check` — passed: `Task 17 keyboard menu policy checks passed`.
- `swift -e 'import AppKit; func hasMarkedText(_ responder: NSResponder?) -> Bool { (responder as? NSTextInputClient)?.hasMarkedText() == true }'` — passed, confirming the native IME marked-text API type-checks.
- Source audit for private inspector selectors/KVC — no matches.
- No Xcode MCP build ran; primary owns serialized builds. No application, browser fixture, hosted test, formatter, or `xcodebuild` ran.

Pending runtime cases: normal/private/Mini/auth focus changes; Cmd-W auth cancellation and Cmd-T routing; menu state as tabs load, fail, hibernate, close, or change peeks; no-window Settings; stale dynamic history/bookmark/window entries; Downloads focus; Control-Tab preview/cancel/release with VoiceOver and active IME composition; blank/unmounted address-bar `mailto` copy and external-app confirmation; alert cancellation when tab/window/focus/document changes; Safari Develop-menu discovery and live inspector preference changes.

Migration, compatibility and private-data impact: adds local Defaults key `webInspectorEnabled`, default false, excluded from portable sync. Private visits remain in current private Browser memory and only appear in the private focused session's current menu. Private bookmarks are hidden from the menu. External address prompts do not store URLs or website content. No schema or entitlement change.

Capability gates / unresolved issues: WebKit offers public `WKWebView.isInspectable`, but no public embedded inspector-open or inspect-element API. Safari's Develop menu is the only advertised host. iOS generic external-app confirmation remains packet 32. The archive helper introduced by packet 10 is included here with its narrow navigation-state correction; packet 10 still owns its separate implementation and review.

Merge prerequisites / follow-up ownership: primary source review and serialized Mac Xcode MCP build. Copy `22931e5`'s isolated archive-state hunk to packet 10. Retain native keyboard, external prompt, Safari Develop, and multi-window runtime acceptance gates. No push, merge, project-file edit, private API expansion, hosted test, or app launch occurred.

## Primary review — 2 October 2026

Reviewed every changed production owner and all URL-load callers, static/dynamic command installation, focused auth/normal/private/Mini targeting, IME/modifier exclusions, public inspector opt-out and explicit blank-address prompt ownership. Corrected nonexistent menu lookup label and nested explicit-self compiler errors. Xcode MCP exact17 project, workspace `workspace-HLfUj14vHh`, `astra` / `My Mac`: build passed13.075s, no errors. Production native-flags/availability/ownership check and native IME API typecheck pass; no app or hosted test.10 helper `8a38e42` copied as `60331bc`; helper correction `22931e5` already copied back10 as `20b08ad`. When combining17 into10, omit both helper-only commits; combine17 source checkpoints `8d069ce`, `ca00469`, `bf6d6c0`, `3d96655`, `1e37413` and primary review checkpoint. Preserve native/runtime/iOS/public inspector gates.
