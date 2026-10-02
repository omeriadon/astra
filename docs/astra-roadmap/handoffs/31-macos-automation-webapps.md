# 31-macos-automation-webapps

Task / selected scope: Packet31 macOS integration plus standalone website Dock apps. Generic automation/Handoff/Spotlight remain optional and unselected.

Branch / baseline: `astra/roadmap/31-macos-automation-webapps`; original packet baseline `6d0385273f0ff12076d15a39736f9efbbfe6e082`. Final integration must still merge the actual packet08/17/23/27/28 results before treating this branch as cumulative.

Status: source and Xcode project wiring are present. Xcode project-format parsing/build, signed-helper behavior and LaunchServices/Dock runtime verification remain for the user's Mac.

Implementation checkpoints include the website-app registry/UI/helper source, signing-preservation correction `a21fd1a32254580aaf9d68e275f640d4b5551731`, helper entitlements `2bf8709ed277f6e4a8779724e6f08d289c5a0829`, and helper-target/project wiring `4697f743f119d6ac7ece25e194fb15fa2ad6d775`.

Implemented behavior:

- `BrowserWebsiteAppPolicy` validates credential-free HTTP/HTTPS launch URLs, bounded safe names, stable UUID-derived bundle identifiers and collision-resistant bundle filenames.
- `BrowserWebsiteAppRegistry` persists a bounded device-local installation registry under Astra Application Support. Installation copies only Astra's bundled `AstraWebsiteAppTemplate.app`, rewrites bounded Astra-owned bundle metadata, optionally applies a captured page icon, re-signs the generated copy and records it only after all steps succeed.
- Generated-app signing now extracts the helper template's signed entitlements before mutation, reuses those entitlements for the local ad-hoc re-sign, verifies the resulting signature, and re-signs after rename/icon mutation so those changes do not leave an invalid code signature.
- Registry operations cover launch, reveal, rename, icon replacement, system-assisted Keep in Dock and uninstall. Mutation/removal paths verify the generated app remains inside Astra's owned WebsiteApps/Apps directory.
- Permanent silent Dock pinning is not claimed. The public path launches/reveals the app for the normal system/user Keep in Dock flow; Astra does not edit Dock preferences or use private APIs.
- `BrowserWebsiteAppsSettingsView` provides launch, rename, reveal, Keep in Dock, icon replacement and uninstall management.
- `BrowserWebsiteAppMenuIntegration` adds **File → Add Website to Dock…** for a committed loaded non-private non-Mini non-internal HTTP/HTTPS page. Confirmation revalidates browser/tab/controller/navigation generation so a navigation race cannot install the wrong page.
- `BrowserWebsiteAppView` / `BrowserWebsiteAppWindowController` provide single-window standalone Astra chrome. Top bar is shown by default and Command-S toggles it only in the helper process.
- `BrowserWebsiteAppHelperMain` is gated by `ASTRA_WEBSITE_APP_HELPER`; normal `browserApp` excludes its own `@main` under that condition.
- `BrowserWebsiteAppNavigationPolicy` keeps same-site/subdomain navigation in the standalone app while unrelated validated HTTP/HTTPS destinations hand off to the system browser path.
- `astra/Special/AstraWebsiteAppTemplate.entitlements` defines the helper's sandbox/network/file/camera/audio/location capability source.
- `astra.xcodeproj/project.xcproj` now declares a macOS-only `AstraWebsiteAppTemplate` application target, shares the `astra/` source folder with that target, defines `ASTRA_WEBSITE_APP_HELPER`, attaches the helper entitlements/packages, adds the helper as a dependency of the main app, and embeds `AstraWebsiteAppTemplate.app` in the main app's Resources with code signing on copy.

Project/build tail still pending:

1. Open the packet31 worktree in Xcode 27.2 and verify `project.xcproj` parses/canonicalizes successfully.
2. Build both `astra` and `AstraWebsiteAppTemplate`; the main target must not define `ASTRA_WEBSITE_APP_HELPER`, while the helper target must.
3. Confirm the built main app contains `Contents/Resources/AstraWebsiteAppTemplate.app` and that its embedded helper signature/entitlements are valid before runtime copying.
4. Verify whether the helper target should set `SKIP_INSTALL=YES` for archive behavior after Xcode inspection; do not guess this in source without archive evidence.
5. Verify `/usr/bin/codesign` execution and ad-hoc re-signing of the copied helper are allowed from Astra's sandbox. If macOS blocks that supported-path attempt, revise the distribution/install architecture rather than bypassing sandbox/signing controls.

Session/cookie ownership: a generated site app has its own application identity/process and Browser session. It does not export the main browser's live WebView, credentials or private session state. Exact persistent WebKit data-store behavior for generated identities remains a runtime case.

Verification asset: `checks-31-website-apps.swift` covers bundle identity, name/path validation, scheme/credential rejection, same-site/subdomain navigation containment and filename sanitization. Run it with production policy files on macOS after Xcode project validation.

Pending runtime acceptance:

- Create an ordinary website app and verify cold/warm launch plus unique running Dock identity.
- Verify generated copies remain launchable after metadata/icon changes and local re-signing.
- Verify Command-S toggles only standalone top chrome.
- Verify same-site navigation remains inside while unrelated links hand off correctly, including OAuth/login edge cases.
- Verify custom favicon/title, rename, moved/missing generated bundle, reveal, Keep in Dock and uninstall.
- Verify uninstall preserves website data unless a separate explicit clear-data operation is selected later.
- Verify duplicate display names remain distinct through UUID bundle IDs/filenames.
- Verify private pages cannot invoke creation and no private cookies/history are exported.

Data/privacy/sync impact: registry metadata and generated executable paths are device-only. No executable path, local code signature, Dock state, credential, cookie or private page data is added to portable sync.

Public API boundary: application launching/reveal uses AppKit/NSWorkspace. Permanent Dock pinning remains system-assisted; no private Dock API is used.

Merge prerequisites: packet08,17,23,27,28 plus packet12 download behavior for the final integrated standalone browser. User-controlled integration only.
