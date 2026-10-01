# 14-address-search-config handoff

Task / selected optional scope: Full packet scope. Search engines, custom HTTPS templates, keyword shortcuts, address classification/display and optional remote suggestions.

Branch / worktree / baseline commit: `astra/roadmap/14-address-search-config`, `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/14-address-search-config`, baseline `0159f9ffdf97ef0fbafd5485adc5222d83b56d4f`.

Status: macOS build verified before the final parser guard; the guard and helper suite compile and pass locally. Runtime/provider acceptance remains pending.

Commit(s), or explicit uncommitted state: `23be171` (`configure address search`), `cba6b412fd8ce1fba6a829a5422c238d009feb05` (`harden address search configuration`), `2a75812f82c6d387aa25421ae35241c321638482` (`record address search build`), plus the parser-correction checkpoint reported to the primary.

Changed files and behavior:

- `astra/UI/AddressBar/BrowserAddress.swift`, `BrowserAddressField.swift`: conservative URL/query classification, safe pasted wrappers, host/port handling, restricted scheme rejection, provider-aware query display and highlight ranges.
- `astra/Models/Search/BrowserSearchConfiguration.swift`, `BrowserSearch.swift`: normal/private Google, DuckDuckGo, Bing or custom provider selection; validated bounded HTTPS query templates; up to20 validated keyword shortcuts; query URL generation and provider-aware labels. Main address-bar and new-tab submissions use this same configuration and the owning browser's private state.
- `astra/Models/Search/BrowserSearchSuggestions.swift`, `astra/UI/Content/NewTabView.swift`: only Google and DuckDuckGo suggestions are implemented. Unsupported or custom providers do not fall back to Google. Reads are capped at131072 bytes while streaming and the URLSession task is cancelled on exit. Suggestions respect the global toggle and explicit private-mode opt-in, and task identity/rechecks cover query, provider/configuration, session privacy and enabled state. Existing `newTabGoogleSuggestions` storage name is retained to avoid packet05 shared-file edits.
- `astra/Storage/BrowserDefaults.swift`, `astra/UI/Settings/Detail/BrowserGeneralSettingsView.swift`: deterministic Google defaults, synced portable search configuration, normal/private engine pickers, HTTPS template editing/validation feedback, keyword shortcuts and private suggestions opt-in.
- `docs/astra-roadmap/checks-14-address-search.swift`: no-network checks using the production address/configuration helpers.

Acceptance cases satisfied, with evidence: Executed the helper check across explicit and scheme-less URLs, localhost, IPv4/IPv6 with ports, Unicode hosts/paths, wrappers, dotted external application schemes, malformed hostname ports, credential/restricted schemes, malformed custom configuration, built-in and custom providers, static and percent-encoded parameter names, keyword shortcuts, Google regional results, private-provider policy, and query values containing `+ & = % #` plus Unicode. It checks full and dimmed address highlighting, stable sorted JSON encoding, escaped control input within configured field bounds, provider-aware suggestion query encoding, and real Google/DuckDuckGo payload parsing for valid and malformed shapes.

Checks run, scheme/destination/workspace and results:

- `swiftc -o /tmp/astra-address-search-check \
  astra/Models/Search/BrowserSearchConfiguration.swift \
  astra/Models/Search/BrowserSearchMatching.swift \
  astra/Models/Search/BrowserSearchSuggestions.swift \
  astra/UI/AddressBar/BrowserAddress.swift \
  astra/UI/AddressBar/AddressDisplayStyle.swift \
  astra/Web/Navigation/BrowserNavigationPolicy.swift \
  docs/astra-roadmap/checks-14-address-search.swift && /tmp/astra-address-search-check` — passed, `address/search checks passed`.
- `swiftc -emit-module -module-name AstraAddressSearch \
  astra/Models/Search/BrowserSearchConfiguration.swift \
  astra/Models/Search/BrowserSearchMatching.swift \
  astra/Models/Search/BrowserSearchSuggestions.swift \
  -emit-module-path /tmp/AstraAddressSearch.swiftmodule` — passed; confirms URLSession.AsyncBytes APIs and cancellation compile locally.
- `swiftc -frontend -parse \
  astra/Models/Search/BrowserSearch.swift \
  astra/UI/AddressBar/BrowserAddressField.swift \
  astra/UI/Content/NewTabView.swift \
  astra/Storage/BrowserDefaults.swift \
  astra/UI/Settings/Detail/BrowserGeneralSettingsView.swift` — passed.
- `git diff --check` — passed.
- Xcode workspace: `workspace-l7ivJ1QAez`, exact path `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/14-address-search-config/astra.xcodeproj`; scheme `astra`; destination `My Mac` (macOS27.2, arm64).
- Xcode diagnostics before the final parser guard: zero issues for all eight changed Swift files. One parallel request timed out; its standalone retry returned zero issues. The final guard was compiled by the production-helper check.
- Xcode `BuildProject`, `buildForTesting: false`: passed, “The project built successfully.” Elapsed20.732 seconds; no errors. Log: `/var/folders/s_/ms68q0zx137_d7r08rxtnp9w0000gq/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261001-175128.txt`.
- Closed only task workspace `workspace-l7ivJ1QAez`. No app launch or hosted tests.
- The final explicit-authority parser guard was compiled in the current no-network `swiftc` helper check. No additional Xcode build was run; the primary reserved the IDE for packet05 and noted the downstream PiP build will verify integration.

Checks written but not executed: None for the helper checks; the written check file was executed. No hosted app tests were run.

Pending runtime/hardware/provider cases: actual address bar/settings interaction; live Google and DuckDuckGo suggestion response formats, cancellation and timeouts; no-network/offline behavior; explicit private-mode remote opt-in. No app or browser was launched.

Migration, compatibility and private-data impact: Missing setting uses the deterministic built-in Google defaults. New portable preference `browserSearchConfiguration` is registered in `Defaults.Keys.syncedSettingNames`, so existing timestamped settings cache/merge persists real changes; decode/read does not stamp. Invalid remote JSON disables search via an invalid custom configuration rather than silently routing text to Google. Private tab data and credentials are not added. Remote private suggestions remain disabled by default. The user-selected search configuration, including a custom HTTPS template and private suggestion opt-in, is a synced preference. Existing normal/private search engine choice is persisted on device.

Capability gates / unresolved issues: Suggestions are implemented only for Google and DuckDuckGo. Bing and custom providers retain local search but do not fetch remote suggestions. Live provider acceptance is pending runtime checks. No server changes.

Merge prerequisites / follow-up ownership: Packet14 was brought forward because its reserved files are disjoint from packet05's permissions-writer files; this does not mark packet17 complete. The final parser guard passed production-helper compilation and checks; downstream PiP Xcode build covers integration.

Primary close-out: source and production-helper checks reviewed. The Mac build passed before the final small dotted-scheme parser correction; current production-helper compilation/checks pass after it. Independent14 remains separate from cumulative05. The user requested finishing up, so no integration or new packet was started. The authoritative next dispatch is in ../05-permissions/docs/astra-roadmap/CONTINUE.md relative to the worktree parent.
