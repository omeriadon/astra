# Manual runtime verification — Astra macOS

This checklist contains behavior that source review and CI compilation do not prove. Completed computer-use checks below apply only to their stated cases; unchecked broader scenarios remain required before release. iOS/iPadOS is no longer an active Astra target and is intentionally excluded.

## Computer-use verification — 4 October 2026

Tested the local Debug app built from `f4307a17235f93b062851a7d3e300a1f3c1b15c0`; final merge `3cdb4cbe4d59794a6f23b0d5044d0a6b3603c15c` has the same source tree. The UI diagnostic export reported Astra `0.0`, build `3`, macOS `27.2 (26B5091g)`, and system WebKit `22625.2.5.11.1`.

Evidence came from native accessibility state and rendered screenshots through computer use. A loopback HTTP fixture at `127.0.0.1:8765` supplied disposable pages, links, a file download, authentication and upload controls. No app behavior was inferred from compilation.

The existing **Home** space was not deleted, renamed, or intentionally edited. A separate **Runtime Verification** space was created. Spaces share the normal browsing data universe; the test space is not a privacy boundary. Existing downloads, history, bookmarks, account state and website data were not cleared. No reset, forced termination, network disruption or performance claim was attempted.

### Checks completed

- [x] Launch the exact local build when Astra was absent from the running-app inventory; observe a usable restored normal window and existing spaces/tabs. This does not prove a fresh-profile launch or quit/relaunch restoration.
- [x] Create and rename a separate test space; open a new tab there without deleting Home.
- [x] Navigate to a public HTTPS page and the loopback HTTP fixture; observe corresponding encrypted/not-secure connection descriptions.
- [x] Follow the fixture's link to its second page; Command-[ returns to the first page and Command-] returns to the second.
- [x] Command-L plus an explicit paste receives a complete URL and Return navigates to it.
- [x] Enter `omeriadon/astra` in New Tab and observe the actual GitHub repository URL and rendered repository page.
- [x] Type a fixture-title query into the loaded address bar, select a history suggestion with Down, and press Return; observe the fixture page rather than a search result.
- [x] After explicitly clicking the Find field, enter `domain` and press Return; visually observe matching text highlighted on the page. The Command-F focus defect below prevents a keyboard-only pass.
- [x] Zoom In toolbar buttons increase displayed zoom; Command-minus decreases it and Command-0 resets it to 100 percent. Keyboard Zoom In remains unverified.
- [x] Twelve consecutive Command-T actions create twelve distinct disposable tabs. Closing and reopening results are qualified below.
- [x] Command-Shift-T reopens a recently closed disposable tab.
- [x] Command-comma opens Settings; the extension-management page is reachable.
- [x] Open bundled Dark Reader and uBlock Origin Lite popups and inspect their rendered controls.
- [x] Toggle Dark Reader only for the loopback fixture: its rendered page changes dark → light → dark. Restore its original enabled state for that test site; do not change its global mode.
- [x] Open the Chrome Web Store from Astra, search for JSON Formatter, visit the verified publisher's listing (`bcjindcccaagfpapjjmafapmmgkkhgoa`, version `0.10.2`), and use Astra's Install Extension button. Observe package acquisition followed by permission review. Deny all-website access and confirm **JSON Formatter, Off** in Settings. Enabled operation was not tested.
- [x] Open Safari Extensions in the App Store from Astra. Search for Refined GitHub and observe **Open**, indicating its app was already installed. Use Astra's **Install Refined GitHub** route, observe permission review, deny access, and confirm **Refined GitHub, Off**. This verifies importing an existing App Store app's extension, not downloading a new Safari app or enabled operation.
- [x] Download the disposable fixture file; observe completion, automatic renaming to `network-test.txt`, and Show in Folder selecting that file. Read only this known test file to verify all `1,114,112` bytes match the fixture. SHA-256: `1a8472174f074fb5d1374fa047e5ad29418ca725cd22a0ae73dfc715c916f494`.
- [x] Command-Shift-N opens a private window with an empty private start page and no normal-session downloads/history modules. A private navigation to a unique loopback URL shows no normal extension action buttons.
- [x] Copy Diagnostics in that private window; paste it into an unsent local test field and inspect JSON. Scope is `private-redacted`, events are empty, and URL, navigation failures and tab counts are absent. Application/build/OS/WebKit metadata remain present as expected.
- [x] Closing the private window after editing its disposable form triggers an unsaved-changes warning. Confirm closing that test window and observe the normal window again. Memory/store teardown was not inspected.

### Observed failures and limits

| Case | Observed result | Follow-up |
| --- | --- | --- |
| Command-F focus | Find bar opens, but subsequent typed text goes into the address field. Clicking Find manually produces real page highlights. | Reproduce with a physical keyboard and fix focus ownership before claiming keyboard-only Find works. |
| Rapid Close Tab burst | Twelve Command-W actions removed eleven of the twelve newly created tabs. One additional press closed the remaining disposable tab and returned to the original fixture. No main-space tabs were closed. | Reproduce paced and rapid input; distinguish application event handling from automation delivery. |
| Keyboard Zoom In | Command-plus, Command-equals and Command-Shift-equals produced no observed zoom change; toolbar Zoom In, Command-minus and Command-0 worked. | Verify physical-keyboard/menu binding. This is not a confirmed application defect because key synthesis may differ. |
| Fast typed URL | One synthesized URL-entry sequence produced reordered text and an unintended search. Atomic paste produced the correct URL and navigation. | Reproduce manual typing and fast keyboard input; do not classify the automation result alone as a parser failure. |
| Accessibility of inactive content | Normal-window AX snapshots included HTML from multiple inactive tabs while another page or Settings was visible. | Run VoiceOver and check traversal/focus isolation. AX visibility alone does not prove what VoiceOver announces. |
| Computer-use connection | After the private-window close, actions/rebinding returned `cgWindowNotFound`. Reset and exact-path/name rebinding failed; Finder failed too, although inventory still reported both apps running. | Restore the computer-use connection or perform the remaining UI checks manually. Do not treat the tool failure as an Astra crash. |

### Remaining checks requiring the user or a restored UI connection

The existing checklist below stays unchecked wherever its full scenario was not exercised.

- **User involvement required:** camera/microphone output and OS prompts, location/privacy decisions, VoiceOver announcements, physical keyboard reproduction of the anomalies, multi-client authenticated sync/conflicts, real provider/DRM restrictions, acceptable performance thresholds and Instruments measurements, production credentials/signing/notarization, and an actual Sparkle update from an older build.
- **Sensitive existing data:** do not reset global settings, clear history/site data, change sync endpoints/accounts, force-kill the app, or disrupt the network during this session. Verify those in a disposable data environment or with a user-controlled backup. The main space is not a disposable fixture.
- **Extension permission decision:** enabled JSON Formatter/Refined GitHub operation remains pending because it would grant new access to existing browsing data. Both newly imported extensions were left **Off**. Test them only after deliberately approving the requested permissions; a separate Space does not isolate that access.
- **Feasible after UI recovery but not completed here:** normal-history exclusion of the private-only marker, quit/relaunch persistence, additional normal windows, HTTP-auth success/cancel/wrong password, upload picker/cancel using a disposable file, Reader/source/export, start-page customization, per-origin preference propagation, native rule import/invalid-update/removal, media/PiP fixtures, and website-app install/rename/icon/removal.
- **Residual test state:** Runtime Verification space and its remaining test tabs were left for inspection; disposable burst tabs were closed. JSON Formatter and Refined GitHub are installed in Astra but disabled. `Downloads/network-test.txt` remains. The loopback fixture server was stopped after recording results. No test space, user file, extension package, or download entry was permanently deleted.

## Launch, restoration and windows

- [ ] Launch Astra from a clean quit and confirm the first window is usable.
- [ ] Quit and reopen with tabs, spaces, favourites/pins and folders; confirm the session restores without duplication or loss.
- [ ] Open multiple browser windows, make changes in more than one window, close them in different orders, and confirm shared state does not regress to an older snapshot.
- [ ] Force an unclean termination and confirm the next launch follows the intended recovery behavior without corrupting saved state.
- [ ] Confirm hibernated tabs restore to the correct URL and selected tab/space remains correct.

## Private browsing and isolation

- [ ] Open normal and private windows together and confirm private history/session state does not appear in normal browsing or sync state.
- [ ] Close the last private window and confirm its WebKit/session-owned ephemeral state is torn down.
- [ ] Exercise downloads, zoom, external-app prompts, permission prompts, exports and diagnostics from a private window and confirm messages/actions remain scoped to that private session.
- [ ] Confirm private diagnostic export is redacted and contains no tab counts, navigation failure details or stored diagnostic events.

## Navigation, failures and internal pages

- [ ] Exercise address-bar navigation, redirects, back, forward, reload and stop on several real sites.
- [ ] Exercise address suggestions, arrow/Return/Escape/Tab selection, explicit clipboard paste, GitHub repository shorthand and guarded history-suggestion deletion.
- [ ] Discover a published OpenSearch engine, confirm or cancel the setting change, and verify tab/navigation/query changes invalidate stale discovery results.
- [ ] Exercise offline failure, network restoration and retry; confirm non-idempotent requests are never replayed automatically.
- [ ] Exercise web-content-process termination/recovery and repeated failure handling.
- [ ] Open every supported `astra://` internal destination from user-facing entry points and confirm malformed/unknown internal URLs fail safely.
- [ ] Exercise external schemes such as `mailto:` and another installed-app scheme and confirm the expected confirmation/ownership behavior.

## Permissions, authentication and uploads

- [ ] Test camera allow/deny and temporary/persistent site decisions.
- [ ] Test microphone allow/deny and temporary/persistent site decisions.
- [ ] Test location allow/deny and temporary/persistent site decisions where available.
- [ ] Confirm permission state is revoked/updated correctly after navigation and capture ends.
- [ ] Test HTTP authentication success, cancellation and wrong credentials.
- [ ] Test a file upload from a normal file input, including canceling the picker.
- [ ] Confirm OS-level privacy prompts and site-level decisions agree with Astra's UI.

## Downloads

- [ ] Download a small file and a large file; verify destination, progress, completion and Reveal/Open behavior.
- [ ] Pause/resume/cancel where supported and verify no corrupt partial file is presented as complete.
- [ ] Test a download whose request contains `Referer`, `Accept` or another explicit custom/signed header and confirm Astra leaves that transfer owned by WebKit rather than replacing it with a bare segmented request.
- [ ] Test download-folder selection and security-scoped/bookmark access across relaunch.
- [ ] Drag a completed download out of Astra.
- [ ] Confirm private-window download behavior does not persist private browsing state beyond the intended file itself.

## History, bookmarks, site data and settings

- [ ] Browse enough pages to exercise history insertion, ordering, search and clearing.
- [ ] Add/edit/delete bookmarks and reading-list/favourite state; relaunch and verify persistence.
- [ ] Exercise website-data/preferences controls and confirm clearing/deleting acts on the intended scope only.
- [ ] Exercise content-blocking settings and per-site behavior.
- [ ] Change per-origin zoom, content mode and custom user agent; verify propagation, relaunch, synchronized zoom and device-only preferences.
- [ ] Customize start-page module visibility/order and verify private-window content remains isolated.
- [ ] Change representative portable and device-only settings and relaunch.
- [ ] Use **Reset Browser Settings** and confirm browser preferences return to defaults while history, website data, bookmarks, downloads, extensions, credentials and account data remain intact.

## Extensions and content blockers

- [ ] Enable and disable each supported bundled/installed extension.
- [ ] Exercise extension permissions and verify denied scopes remain denied.
- [ ] Open extension UI/popup/window surfaces that are supported.
- [ ] Trigger or simulate an extension load failure and confirm Astra fails safely without exposing private browsing data.
- [ ] Confirm extension/content-blocker state survives relaunch as designed.
- [ ] Import, update, disable and remove a native JSON rule list; verify invalid updates preserve the last good list, redirects respect site exceptions, and private rules remain session-owned.

## Sync

- [ ] Start offline and confirm cached local history, bookmarks, spaces and settings remain usable before any network response.
- [ ] Verify sync-server address normalization for the forms you actually use, including uppercase `HTTPS://` and a host/port with omitted scheme if applicable.
- [ ] Sign in/authenticate, sync, relaunch and confirm the cached state remains available before hydration completes.
- [ ] Edit the same entity on two clients and confirm `modifiedAt`/last-updated conflict handling produces the intended deterministic winner.
- [ ] Test deletions/tombstones and history-clear metadata across clients so deleted data does not reappear.
- [ ] Test space/order/selection-related sync data and representative portable settings.
- [ ] Confirm device-only settings stay device-only.
- [ ] Confirm private-window data is excluded from sync documents.
- [ ] Change endpoint/account while a request is in flight and confirm an old response cannot be applied to the new endpoint/account.

## Reader, translation, source and page tools

- [ ] Test Reader on an eligible article and an ineligible page.
- [ ] Test translation on supported content/provider availability, including failure/cancel behavior.
- [ ] View page source and confirm the source belongs to the intended page.
- [ ] Exercise supported page export formats and destination selection.
- [ ] Exercise context-menu and drag actions for links/images/text/files that Astra exposes.

## Media and Picture in Picture

- [ ] Exercise HTML media play, pause, mute/unmute and tab/media indicators.
- [ ] Enter and leave Picture in Picture from a supported main-frame video.
- [ ] Test PiP on at least one provider-controlled/DRM page and record provider restrictions rather than treating a provider rejection as an Astra success/failure automatically.
- [ ] Exercise iframe and multiple-video pages and confirm Astra does not claim control/state it cannot observe.
- [ ] Confirm active media/PiP, camera/microphone capture, active downloads and unsaved form state are protected from destructive hibernation/optimization where intended.

## Website apps and macOS integration

- [ ] Create a website app, launch it independently and confirm its navigation scope.
- [ ] Test duplicate creation/update/removal behavior.
- [ ] Verify generated website apps retain helper entitlements after install, rename and icon updates, and that failed installation leaves no registry entry or partial bundle.
- [ ] Confirm out-of-scope navigation returns to the browser or otherwise follows the documented policy.
- [ ] Exercise Mini Astra/global shortcut behavior if enabled.
- [ ] Confirm default-browser registration and opening web links from another macOS app.

## Accessibility

- [ ] Navigate primary browser chrome using only the keyboard.
- [ ] Run VoiceOver through address bar, tabs, navigation controls, settings, downloads and dialogs; verify labels and focus order are understandable.
- [ ] Trigger transient toasts and confirm VoiceOver announces them once without requiring focus movement.
- [ ] Load a page and confirm loading progress is exposed as frequently updating rather than a static unlabeled decoration.
- [ ] Enable Reduce Motion and confirm browser-owned animations respect it where intended.
- [ ] Increase system text/accessibility sizes and confirm transient toast text can expand without being forced to one line.
- [ ] Check high-contrast/Increase Contrast appearance and keyboard focus visibility on major controls.

## Diagnostics and privacy

- [ ] Copy diagnostics in a normal window and inspect the JSON.
- [ ] Confirm exported diagnostics contain no page text, form values, credentials, full URLs, query strings or tokens.
- [ ] Copy diagnostics in a private window and confirm the report scope is `private-redacted` with private browsing details omitted.
- [ ] Generate enough diagnostic events/data to exercise the bounded export path; confirm Astra refuses an oversized report instead of copying unbounded data.

## Performance measurements

Do not treat these as pass/fail until you choose acceptable thresholds. Record hardware, macOS build, Astra commit/version/build, WebKit build, power mode and Debug/Release configuration with every result.

- [ ] Measure launch-to-usable-window and selected-page completion with 1, 10, 50 and 100 restored tabs; repeat each scenario five times.
- [ ] Measure loaded-to-loaded, loaded-to-hibernated and hibernated-to-loaded tab switching, including switches across spaces.
- [ ] Record Astra + WebContent + Network process memory at 1, 10, 25, 50 and 100 tabs after a stable idle period.
- [ ] Repeat representative memory measurements after memory pressure and confirm only eligible tabs are hibernated.
- [ ] Measure a fixed slow/large-page scenario and separate navigation start, commit and finish from post-commit responsiveness.
- [ ] Use Instruments for any optimization claim; do not infer performance wins from source inspection alone.

## Release, signing and Sparkle

- [ ] Run the release validation helper/self-test on the release branch you intend to ship.
- [ ] Produce the final Release archive using the distribution configuration you already use.
- [ ] Verify the app is signed with the intended identity and entitlements; do not silently introduce a different sandbox/entitlement model during roadmap integration.
- [ ] Complete Developer ID/notarization/stapling/Gatekeeper checks when credentials are available.
- [ ] Validate the Sparkle appcast/signature and download URL against a real published artifact.
- [ ] Install an older Astra build, check for the new update, download it, install/relaunch and verify the resulting version/build.
- [ ] Exercise manual check, automatic check/install settings, skip/later behavior and one failed/retried update path.

## Product-scope decisions

- [ ] Confirm the shipped product intentionally uses **Spaces**, not a fake Profiles layer. True isolated profiles are not part of this release.
- [ ] Confirm there is no Watch target/scheme/embed phase remaining.
- [ ] Confirm iOS/iPadOS is not being treated as a release target; no new iOS verification is required for this macOS release.

## Source corrections after the 4 October runtime reports

These are local source changes following the screenshot and the 9.585-second screen recording. They have not been runtime-verified on YouTube or in the user's normal session. The earlier completed checks remain historical evidence for the earlier build, not passes for this changed build.

Implemented:

- Find displays the current match and total for visible main-document HTML text, with forward/backward wrapping, literal case-insensitive matching, and Unicode-safe range offsets. Command-F explicitly transfers focus away from the address field. PDF/non-HTML documents retain native WebKit search when DOM search is unavailable; their numerical count is unavailable. Cross-origin frames and shadow DOM still need coverage decisions/testing.
- Media events no longer directly assert audible playback. The snapshot distinguishes audible playing/paused media from muted or silent video and protects genuinely running muted video from destructive hibernation separately. Concurrent refreshes are coalesced. This does not prove absence of silent encoded audio tracks or cross-frame audio; those remain runtime cases.
- PiP eligibility is recomputed from the current video and its public capabilities without depending on a previously injected helper function. Metadata/data/canplay/resize changes request fresh eligibility. A failed entry attempt no longer permanently disables future eligible attempts. Provider/user-gesture restrictions are preserved; native YouTube menu availability is not claimed verified.
- Website content, viewport changes and committed space/theme switches no longer interpolate/fade. Tab titles use native buttons, and selection is published before deferred hibernated-controller preparation. No zero-frame timing guarantee or measured frame-rate claim has been made.
- Additional normal windows reuse current in-memory tabs/workspace instead of displaying a disk-restoration placeholder. Window transparency/material-compatible background is configured before display; hosted layout/display is prepared before ordering front and native window-opening animation is disabled. Cold first-launch hydration and first-frame appearance still need a recording of the changed build.
- Normal windows share a tab object/controller per tab ID and session. Only its display owner mounts the live WebView; ownership moves when the window activates. Other windows show a dimmed cached image or an unavailable placeholder and reject page/tab hit tests. Extension tab bridges follow the owner, closing one window preserves tabs referenced by another, and full application quit still forces final teardown. Private and Mini sessions remain separate.
- Mini Astra uses the same double-Command-Q feedback modifier as normal windows, and the quit request targets the focused browser rather than the normal-window registry.
- Native viewport-inset writes are skipped when their values have not changed.

Agent-runnable evidence:

- `bun checks/find-count-check.mjs`: production Find script count, position, forward/backward wrap, reset, literal metacharacters and Unicode offsets.
- `bun checks/media-activity-check.mjs`: production media script excludes absent/muted/zero-volume/silent/ended media from audible-playing badges, recognizes actual audio and paused progress, and protects running silent video independently.
- `bun checks/picture-in-picture-check.mjs` and `bun checks/media-mute-check.mjs`: existing production-script checks.
- `swiftc astra/Models/Core/BrowserWindowRegistry.swift checks/window-ownership-check.swift -o /tmp/astra-window-ownership-check && /tmp/astra-window-ownership-check`: production registry ownership/transfer/close/private-isolation behavior with minimal boundary fixtures. It does not instantiate WebKit or prove AppKit reparenting.
- Xcode MCP builds of `astra` / `My Mac` completed successfully during implementation. Final Xcode MCP build after all changes passed with zero errors in 30.972 seconds. Log: `/var/folders/s_/ms68q0zx137_d7r08rxtnp9w0000gq/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261004-195331.txt`.

Required runtime follow-up on this changed build:

- [ ] Repeat Command-F with the address field focused; verify counts/current selection for real pages, changing DOM, literal symbols, Unicode, iframe/shadow/PDF content and dismissal.
- [ ] Open Google search and YouTube home with no user-started playback; confirm no false playing-audio card. Exercise muted, audible, paused, ended and embedded players.
- [ ] Reproduce YouTube's initial stuck page, reload recovery, actual video lag and native/menu-bar PiP availability. Compare against Safari and collect a Release Instruments trace if lag remains.
- [ ] Record first display of both a cold launch and an additional window; verify no late background/theme setup and no page/viewport startup animation.
- [ ] Switch warm and hibernated tabs quickly; verify immediate chrome selection and absence of page fade/offset animations.
- [ ] Select one tab in two windows, alternate focus, navigate/play media, and close each window in turn; verify one live view/state, dimmed noninteractive inactive presentation, correct extension/prompts/history routing and continued playback where expected.
- [ ] Press Command-Q once in Mini Astra; verify its banner appears, expires, and a timely second press follows the existing quit confirmation/data-saving flow.

No existing space, account, download or browsing-data reset was performed as part of these source changes.
