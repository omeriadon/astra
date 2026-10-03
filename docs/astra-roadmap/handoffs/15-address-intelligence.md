# 15 Address intelligence handoff

Task / selected optional scope: Shared address and new-tab search projection, clipboard URL paste, and explicit OpenSearch discovery.

Branch / worktree / baseline commit: `astra/roadmap/15-address-intelligence` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/15-address-intelligence` / `ff82e26`.

Status: source corrections complete after primary review; a fresh primary Mac build and native runtime acceptance are pending.

Commit(s): `91501ab` (`implement address intelligence`) and `fb98be7` (`correct address intelligence flows`).

Changed files and behavior:

- `astra/Models/Search/BrowserSearch.swift`, `BrowserSearchResult.swift`: one projection now backs New Tab and the address bar. It adds bookmark and same-Browser open-tab results. History URLs are grouped and ranked by match, frequency, and recency; ties and destination/type deduplication are deterministic. Open-tab selection revalidates the tab and URL, then selects that tab in the same Browser session. Only the typed address result calls `loadFromAddressBar`; history, bookmark, suggestion, and open-tab routes retain their existing load/selection behavior.
- `astra/Models/Core/Browser.swift`: query generations invalidate selection and pending OpenSearch results when text changes. Address-field query generation is isolated from new-tab query state. Discovery retains the selected tab, controller, live WebView identity, document generation, query generation and search configuration; each is rechecked after metadata fetch and immediately before applying the confirmed setting.
- `astra/UI/AddressBar/BrowserAddressField.swift`, `astra/UI/Content/NewTabView.swift`: address suggestions support arrow selection, Return, Escape, Tab completion, and guarded per-URL history deletion. A labelled discovery button starts the OpenSearch flow from the loaded address UI. Paste uses the native PasteButton, accepts only directly parsed bounded HTTP(S) URLs or host-shaped text, and preserves the pasted target when focus changes. It never inspects the clipboard in the background.
- `astra/Models/Search/BrowserSearchSuggestions.swift`: query request identity includes query generation, address/new-tab scope, tab/controller/document context, provider, configuration, privacy and enabled state. Loaded-address results use separate local state and never reuse New Tab suggestions. Existing streaming byte limits, cancellation, and explicit private suggestion opt-in remain intact. Explicit discovery reads only the current live WebView's published `link[rel~=search]` URL through public `evaluateJavaScript`, then fetches at most 64 KiB of HTTPS XML without cookies or stored credentials. Redirects to non-HTTPS or credential-bearing URLs are rejected before following; native TLS validation remains enabled. Absent metadata, policy rejection, invalid XML and fetch failure report a generic owning-session toast, with no URL or query details.
- `astra/Models/Search/BrowserSearchMatching.swift`: the bounded UTF-8 XML parser rejects DTD/entity declarations before parsing, sets external entity resolution to `.never`, processes namespaces, treats omitted OpenSearch method as GET, and rejects POST, insecure templates, unsupported placeholders and invalid templates. The user must accept a confirmation before the existing portable `browserSearchConfiguration` setting changes; no setting key or config schema was added.
- `docs/astra-roadmap/checks/15-address-intelligence.swift`: standalone production checks cover result ranking/deduplication, selected-result resolution, request generation/scope/privacy identity, private-suggestion opt-in, paste URL/focus handling, stale discovery context, and valid, namespaced, default-GET, invalid, DTD/entity, POST, insecure, unsupported-placeholder and oversized OpenSearch data.

Acceptance cases satisfied, with evidence:

- Repeated history visits produce one URL result, with frequency and recency affecting rank. Same destinations remain distinct across result kinds. Stable ID tie-breaking makes equal-score results deterministic.
- The production check exercises ranked results, duplicate destination/type removal, explicit selection, and no automatic selection. The source guards New Tab and address results against query generation, current query, selected tab, and current search configuration changes.
- Normal autocomplete reads only the current normal Browser. Private results read only the current private Browser's in-memory data; remote private suggestions remain governed by packet14's off-by-default explicit opt-in. Discovery is disabled in private windows.
- Selecting an open-tab result verifies its tab and current active URL before selecting it. Deleting a history suggestion verifies that the same result is still present for the displayed query and removes history only; bookmarks remain.
- Clipboard access is limited to the native explicit PasteButton action. It accepts no more than 16 KiB, parses the URL directly without invoking search fallback, rejects credentials, malformed schemes/hosts/ports and control characters, and preserves the resulting destination when focus changes.
- Loaded-address remote suggestions use an independent cancellable task keyed by query, generation, tab, controller/document, provider, config, private policy, focus and enabled state. Stale requests and result callbacks fail their current-identity checks.
- OpenSearch discovery reads only the current WebView's published search-link metadata after an explicit button tap. It captures and rechecks tab, controller, WebView, document, query and configuration identity after every asynchronous boundary and when the user accepts. No whole page is fetched and no WebView cookies or credentials are sent.
- OpenSearch parsing covers namespace-qualified roots, omitted default-GET method, POST rejection, insecure and unsupported placeholders, DTD/entities, invalid XML and size limits. The write path requires explicit confirmation.

Checks run, scheme/destination/workspace and results:

- `swiftc -frontend -parse` over all changed production Swift sources — passed. This verifies parsing, not Xcode type checking.
- `swiftc -o /tmp/task15-address-intelligence-check astra/Models/Search/BrowserSearchConfiguration.swift astra/Models/Search/BrowserSearchMatching.swift astra/Models/Search/BrowserSearchResult.swift astra/Models/Search/BrowserSearchSuggestions.swift astra/Web/Navigation/BrowserNavigationPolicy.swift astra/UI/AddressBar/BrowserAddress.swift astra/UI/AddressBar/AddressDisplayStyle.swift docs/astra-roadmap/checks/15-address-intelligence.swift && /tmp/task15-address-intelligence-check` — passed: `Task 15 address intelligence checks passed`; this also type-checks the production parser, request model and WebKit metadata/URLSession helper on the local Swift toolchain.
- `git diff --check` — passed.
- No Xcode MCP workspace/build, app launch, hosted test, network discovery request, or runtime UI test ran. Primary owns the serialized Mac build.

Checks written but not executed: no additional checks.

Pending runtime/hardware/provider cases: fresh Mac/iOS target type checking; native PasteButton appearance and paste permission behavior; address-field popup placement, keyboard selection, Tab completion, Return/Escape and VoiceOver; open-tab switching with hibernated tabs and active peeks; actual published OpenSearch link formats and metadata server redirects; confirmation and portable-setting timestamp propagation. No browser or provider was contacted.

Migration, compatibility and private-data impact: no persistence or sync schema change. `browserSearchConfiguration` remains the existing timestamped portable setting and is updated only after user confirmation. No clipboard is read implicitly. Private tabs, history, bookmarks and queries are never projected into a normal Browser; remote private suggestions retain packet14's default-off behavior.

Capability gates / unresolved issues: actual provider availability and redirect behavior need runtime verification. Discovery is explicit and reads only the page's public OpenSearch link metadata; metadata requests are bounded and credential-free. A fresh Xcode build remains pending after source corrections.

Merge prerequisites / follow-up ownership: primary source review and serialized Mac Xcode MCP build. Preserve packet14's suggestion-provider and private-opt-in rules, packet17's address prompt ownership, and packet29's timestamped portable-settings behavior. No defaults key, project file, controller/delegate file, sync schema, hosted test target, or server code changed.

## Primary review — 2 October 2026

Reviewed all changed production files, actual loaded/new-tab/paste flows, query/private/provider identity and history/open-tab lookup, XML boundaries and published metadata discovery/secure redirects, and source identity revalidation at confirmation. Initial confirmation modifier build failure corrected in fb98be7. Exact15 project Xcode MCP workspace `workspace-nHAlqDrYr9`, `astra` / `My Mac`: final build passed12.868s, no errors. Production parser/paste/ranking/ownership check passes. Native focus/popup/PasteButton/OpenSearch/provider/iOS cases remain pending; no app or provider was run.
