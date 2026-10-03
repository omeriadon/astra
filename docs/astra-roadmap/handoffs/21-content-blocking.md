# 21-content-blocking

Task / selected optional scope: Packet21. Keep bundled uBlock Origin Lite as the default blocker and add a separate opt-in native WebKit content-rule-list path for user-selected JSON files. No default feed, remote source, fabricated request counts, or private extension hosting was added.

Branch / worktree / baseline commit: `astra/roadmap/21-content-blocking`; roadmap worktree `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/21-content-blocking`; baseline `6d0385273f0ff12076d15a39736f9efbbfe6e082` from packet20.

Status: source implementation complete and source-reviewed in this continuation; macOS Xcode build and runtime acceptance remain open because this continuation environment has repository access but no Xcode workspace/tooling.

Commit(s): source/model checkpoint `c343dd0cb44212d6e22663ffdc5b27ef84cd21af`; native-rule implementation checkpoint `880ef3352a9db9a929be3ba22dfb75339971fd31`; redirect ownership correction `33de8a9c0f66c22834d43528fda42297cc284b56`; removal resilience correction `867a34c25dc517582ce1e48ae6615d8fd5ac7318`.

Changed files and behavior:

- `BrowserContentBlockingModel.swift` validates bounded user-selected JSON rule lists, limits source/rule/filter sizes, hashes sources into stable compiled-list identifiers, preserves the current last-good list when candidate compilation does not match, and models when a list should apply for a site.
- `BrowserContentBlocking.swift` owns normal/private rule stores, restores or recompiles saved normal rules, imports bounded security-scoped JSON files, preserves the active list on failed updates, supports enable/disable/remove, and keeps private source/settings in memory with a UUID-owned temporary WebKit rule-store directory removed at private-session close.
- Removing rules now always removes Astra-owned saved source/configuration even if WebKit fails to delete its compiled cache. A cache-deletion failure is reported separately and the orphaned compiled list is no longer active.
- `BrowserWebSession.swift` owns the correct normal/private blocker service, prepares normal rules before deferred initial navigation, propagates blocker/source/site-exception changes to same-session controllers, and closes private blocker storage during private-session cleanup.
- `BrowserController.swift` applies/removes only Astra's app-owned native list through each web view's `WKUserContentController`. Main-frame navigation decisions select the destination site's exception before load; cancelled/download navigations preserve the current site's rules. Server redirects restore the native list while the redirected destination is unresolved so a prior site's exception cannot leak into a different origin.
- `BrowserSitePreferences.swift` / `BrowserSitePreferenceModel.swift` add a device-local per-origin native-blocking exception while preserving the existing version-1 local preference format for older records where the new field is absent.
- `BrowserContentBlockingSettingsSection.swift` exposes imported-list status, source revision/rule count, enable/disable, recompile, removal, and JSON import. It explicitly distinguishes the independent bundled uBlock Origin Lite path and does not claim unsupported blocked-request counts.
- `BrowserSiteInformationButton.swift` exposes a per-site toggle for pausing only Astra's imported native list; uBlock Origin Lite remains independent.

Acceptance cases satisfied by source review / focused checks present in the branch:

- Invalid or oversized JSON is rejected before replacement; failed compilation leaves the previous in-memory/source configuration untouched.
- Normal rules and site exceptions persist only in local app state; private rules are off by default and session-owned.
- Site exceptions apply to the app-owned native rule list only, avoiding an implicit policy change to uBlock Origin Lite.
- Native rule enable/disable/removal propagates to live same-session controllers without unsolicited page reloads.
- Removal cannot strand Astra-owned source/configuration because WebKit's compiled-cache deletion failed.
- Redirect handling prevents a previous origin's disabled-rule state from carrying blindly through an unresolved server redirect.

Checks/evidence available:

- `docs/astra-roadmap/checks-21-content-blocking.swift` covers valid/invalid/oversized rule sources, last-good behavior, bounded reads, enable/exception application, navigation-disposition origin selection including redirects, and backward-compatible local-site-preference decoding.
- Current public WebKit documentation confirms `WKContentRuleListStore(url:)` uses the supplied directory for persistent compiled rules and that `WKUserContentController` supports adding/removing individual `WKContentRuleList` objects.
- The final correction commit was inspected after write and contains only the intended removal/error-message changes.

Checks not completed in this continuation:

- No macOS Xcode build or affected-file diagnostics were run here.
- No app launch, WebKit fixture execution, extension operation, file importer interaction, private-window lifecycle run, or hostile/large-list runtime test was performed.
- The focused Swift executable was not rerun here because this environment lacks Apple's `CryptoKit` module; the checked-in test remains the canonical focused check for the macOS worktree.

Pending runtime/provider cases:

- Compile/import a valid small native rule list and verify requests are blocked in normal browsing.
- Verify invalid/update-failed lists leave the prior list active.
- Verify enable/disable and per-site exceptions before direct navigation and after server redirects.
- Verify same-session live tabs update without reload and unrelated sessions remain untouched.
- Verify private imported rules are isolated and the temporary compiled-rule directory is removed on orderly private-session close; crash cleanup remains explicitly unguaranteed.
- Verify uBlock Origin Lite remains independently functional with native rules enabled or disabled.
- Verify compiled-cache deletion failure messaging if that provider failure can be induced.

Migration, compatibility and private-data impact: normal imported source metadata/data uses a versioned device-local UserDefaults record and is not added to portable sync. The packet adds one optional field to the existing local per-site preference document; legacy records decode with the field absent. Private source/preferences are memory-only and compiled through a temporary WebKit rule-list store. No browsing history, credentials, permissions, or synced site-zoom records are changed.

Capability gates / unresolved issues: no remote maintained filter-list provider/update policy/license/privacy contract is selected. WebKit does not expose reliable blocked-request counts for this app-owned path, so none are shown. Native per-site exceptions govern only Astra's imported rule list, not third-party extension behavior. Exact redirect/final-origin exception timing remains a runtime WebKit case. Crash-time deletion of the private compiled-rule directory is not guaranteed.

Merge prerequisites / follow-up ownership: macOS Xcode build/diagnostics should be run against branch HEAD before treating packet21 as build-verified. Packet22 depends on packet21 and should preserve its independent uBlock/native-rule distinction and per-site exception semantics. User-controlled integration only.
