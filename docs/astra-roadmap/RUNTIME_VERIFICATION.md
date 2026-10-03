# Manual runtime verification — Astra macOS

This checklist contains behavior that source review and CI compilation do not prove. Run these checks manually on the final macOS integration build before release. iOS/iPadOS is no longer an active Astra target and is intentionally excluded.

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
- [ ] Change representative portable and device-only settings and relaunch.
- [ ] Use **Reset Browser Settings** and confirm browser preferences return to defaults while history, website data, bookmarks, downloads, extensions, credentials and account data remain intact.

## Extensions and content blockers

- [ ] Enable and disable each supported bundled/installed extension.
- [ ] Exercise extension permissions and verify denied scopes remain denied.
- [ ] Open extension UI/popup/window surfaces that are supported.
- [ ] Trigger or simulate an extension load failure and confirm Astra fails safely without exposing private browsing data.
- [ ] Confirm extension/content-blocker state survives relaunch as designed.

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
