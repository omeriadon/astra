# 22-extensions

Task / selected optional scope: Packet22. Complete and review the existing public WebKit extension-hosting path. Keep bundled/installable Web Extensions, toolbar actions, per-site access, enable/disable/remove, Chrome Web Store CRX3 import, Safari app-extension discovery and private exclusion. Automatic catalog/update sources and private extension hosting remain gated because no provider/update identity policy or isolated private extension design was selected.

Branch / baseline: `astra/roadmap/22-extensions`; baseline `c8e71de1548d18038cb828d97387932346673cc1` from source-reviewed packet21.

Status: source-reviewed and packet check added. Xcode compilation and installed-extension runtime compatibility remain pending for the user's Mac.

Commit(s): focused package check `b87cb66716f02dac6d5f6581589f2ce980e010e9`.

Existing implementation verified:

- `BrowserExtensionManager` uses `WKWebExtensionController`/`WKWebExtensionContext` rather than a custom Chrome runtime. Normal browser tabs/windows are mirrored into WebKit extension tab/window objects and close/focus/property-change callbacks remove stale IDs and contexts.
- Private browsers are excluded from extension window/tab creation, actions and `WKWebViewConfiguration.webExtensionController`, so normal extension contexts cannot enumerate or operate private tabs.
- Enable/disable is stateful and unloads/loads the WebKit context. Installed extensions must match the previously approved permission summary before enabling; changed requested permissions/host patterns trigger a new approval prompt instead of silently inheriting approval.
- Per-site action access is temporary when `allSites` is disabled. File URL access is separately explicit and defaults denied.
- User-selected ZIPs are bounded to 50 MB and handed directly to `WKWebExtension(resourceBaseURL:)`; Astra does not manually extract them, so it does not create an app-owned ZIP traversal surface. WebKit validates the extension manifest and only MV2/MV3 packages are accepted. Failed installs remove the copied package and do not add it to installed state.
- Chrome Web Store import accepts only canonical HTTPS listing IDs, requests CRX3, verifies an HTTPS Google/Googleusercontent response, bounds the download to 50 MB, validates the CRX3 header, and then goes through the same WebKit package validation path.
- Removal disables/unloads first, drops context/installed metadata and deletes only the UUID-owned copied package. Bundled extension resources are never deleted.
- Bundled uBlock Origin Lite remains independent from packet21's optional native rule-list subsystem; both can coexist without pretending that their request counts or policies are unified.

Compatibility surface:

- Supported behavior is whatever public `WKWebExtension` exposes for content scripts, background content, actions/popovers, permissions, storage and WebKit-hosted messaging.
- Astra provides browser tab/window/action lifecycle adapters and permission decisions; it does not emulate missing Chrome APIs.
- Native messaging, automatic extension update feeds/catalogs, private extension hosting and any API WebKit reports unsupported remain explicit capability gates.

Verification asset:

- `checks-22-extensions.swift` exercises the production `ChromeExtensionPackage` parser against valid/invalid Chrome Web Store IDs, CRX3 version/header bounds, malformed packages and the 50 MB package ceiling.
- The check is source-only in this continuation and was not executed because this environment does not contain the local Swift/Xcode workspace.

Pending runtime/build cases:

- Build the branch for macOS and iOS where applicable.
- Install representative bundled, Safari-app and Chrome MV3 packages; verify content scripts, storage, messaging, popovers/actions, permission prompts, per-site grants and unload/remove lifecycle.
- Verify an extension permission expansion cannot become enabled without reapproval.
- Verify normal contexts cannot see private windows/tabs.
- Verify failed/corrupt package import leaves existing installed extensions untouched.

Data/privacy impact: extension enable/access decisions and installed-package metadata remain device-local. No extension catalog, remote update endpoint, private browsing access or synced extension state was added.

Merge prerequisites: packet21 must be integrated first. User-controlled integration only.
