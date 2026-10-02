# 31-macos-automation-webapps

Task / selected scope: Packet31 macOS integration plus the explicitly required standalone website Dock apps. Generic automation/Handoff/Spotlight remain optional and unselected.

Branch / baseline: existing `astra/roadmap/31-macos-automation-webapps`. The branch already existed at `6d0385273f0ff12076d15a39736f9efbbfe6e082` with packet20-era documentation rather than packet31 implementation, so it was preserved and extended rather than force-reset. Final integration must merge the actual packet08/17/23/27/28 results before treating this as cumulative.

Status: website-app source architecture is implemented through the helper-app boundary. Xcode helper target/template wiring, build/signing and LaunchServices/Dock runtime verification remain for the user's Mac.

Implemented source:

- `BrowserWebsiteAppPolicy` validates credential-free HTTP/HTTPS launch URLs, bounded safe names, stable UUID-derived bundle identifiers and collision-resistant bundle filenames.
- `BrowserWebsiteAppRegistry` persists a bounded device-local installation registry under Astra Application Support with creation/update timestamps. Installation copies a bundled `AstraWebsiteAppTemplate.app`, writes only Astra-owned Info.plist metadata, optionally applies the captured page icon through public `NSWorkspace.setIcon`, ad-hoc signs the locally generated app, records it only after all steps succeed, and rolls the copied bundle back on failure.
- Registry operations cover launch, reveal, rename, icon replacement, system-assisted Keep in Dock and uninstall. Mutations verify the path remains inside Astra's owned WebsiteApps/Apps directory before changing or trashing anything.
- Uninstall removes only the generated app bundle and registry metadata. Shared/main Astra website data is never cleared as an uninstall side effect.
- Permanent silent Dock pinning is not claimed: the public AppKit path launches the generated app so it has a running Dock icon and reveals it for the user/system Keep in Dock flow. No Dock preference editing/private API is used.
- `BrowserWebsiteAppsSettingsView` provides the required management page: launch, rename, reveal, Keep in Dock, icon replacement and uninstall, with explicit errors and Dock capability disclosure.
- `BrowserSettingsView.Page.websiteApps` wires that management page into the existing settings router on macOS.
- `BrowserWebsiteAppMenuIntegration` adds **File → Add Website to Dock…** after the AppDelegate has built the native menu. It is enabled only for a committed, loaded, non-private, non-Mini, non-internal HTTP/HTTPS page. The install candidate captures URL/title/favicon and revalidates the same browser/tab/controller/navigation generation when the sheet is confirmed so a navigation race cannot install the wrong page.
- `browserApp` installs the menu integration without editing the large AppDelegate menu implementation.
- `BrowserWebsiteAppView` and `BrowserWebsiteAppWindowController` reuse Astra's Browser model, BrowserContentView, ShellTopBarView and BrowserThemeBackground in a single-window standalone chrome. Top bar is shown by default. Media/PiP teardown protection is retained on close.
- `BrowserWebsiteAppHelperMain` is a helper-only macOS entry point gated by `ASTRA_WEBSITE_APP_HELPER`. It reads the validated launch URL/name from its generated bundle metadata, opens the standalone window and provides Command-S exclusively in the helper process to toggle the top bar. The normal Astra Command-S behavior is therefore unchanged.
- `BrowserWebsiteAppNavigationPolicy` keeps launch-host/www/subdomain navigation in the standalone app; unrelated credential-free HTTP/HTTPS destinations are handed to `NSWorkspace` instead of silently expanding the installed site's scope.

Required Xcode/template wiring still pending:

1. Add a macOS application target/product named `AstraWebsiteAppTemplate` that compiles the shared browser source with `ASTRA_WEBSITE_APP_HELPER` defined. `browserApp.swift` already excludes the normal Astra `@main` under that condition, and `BrowserWebsiteAppHelperMain.swift` becomes the helper entry point.
2. Give the helper the same frameworks/packages needed by the shared Browser/Mini Astra source, macOS-only deployment, outgoing network/camera/microphone/location capabilities as actually required, and no iOS product membership.
3. Copy the built helper product into the main Astra app resources as `AstraWebsiteAppTemplate.app`, matching the lookup in `BrowserWebsiteAppRegistry.install`.
4. Decide/sign the helper-template entitlement model. Generated copies currently rewrite bundle metadata then invoke `/usr/bin/codesign --force --deep --sign -`; verify this supported local ad-hoc generation path under Astra's sandbox. If sandbox execution or writes block it, the install directory/template-signing mechanism must be adjusted before release rather than bypassed.
5. Build both targets. The main target must not define `ASTRA_WEBSITE_APP_HELPER`; the helper target must.

This is intentionally left as the Xcode/build tail because project-format/signing changes cannot be validated safely without the user's Xcode environment.

Session/cookie ownership: the helper is a separate application identity and runs its own Browser process/session. It does not export private session state, credentials or the main browser's live WKWebView into the generated app. Exact persistent WebKit data-store behavior for ad-hoc generated helper identities is a runtime acceptance case; no profile abstraction is invented.

Verification asset: `checks-31-website-apps.swift` covers stable bundle identity, name/path validation, scheme/credential rejection, same-site/subdomain navigation containment and filename sanitization. Run it with the production policy files on macOS after target wiring.

Pending runtime acceptance:

- Create an ordinary non-manifest website app from the File menu; verify cold/warm launch and unique running Dock identity.
- Verify helper copies remain launchable after local ad-hoc signing and across Astra upgrades.
- Verify Command-S toggles only standalone top chrome.
- Verify same-site navigation stays inside while unrelated links hand off correctly, including OAuth/login edge cases that may require an explicit allowlist extension.
- Verify custom favicon/title, rename, moved/missing generated bundle, reveal, re-add/Keep in Dock and uninstall.
- Verify uninstall preserves website data unless a separate explicit clear-data action is later added.
- Verify duplicate display names remain distinct through UUID bundle IDs/filenames.
- Verify private pages cannot invoke creation and no private cookies/history are exported.

Data/privacy/sync impact: registry metadata and generated executable paths are device-only. No executable path, local code signature, Dock state, credential, cookie or private page data is added to task29 synchronization. If metadata sync is selected later it needs the timestamp/tombstone merge contract first.

Public API evidence: `NSWorkspace.openApplication(at:configuration:completionHandler:)` is the supported asynchronous application launch API; no private Dock API is used. Permanent pinning remains system-assisted.

Merge prerequisites: packet08,17,23,27,28 plus packet12 download behavior for the final integrated standalone browser. User-controlled integration only.
