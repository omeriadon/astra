# 15 Address intelligence handoff

Task / selected optional scope: Shared address and new-tab search projection, clipboard URL paste, and explicit OpenSearch discovery.

Branch / worktree / baseline commit: `astra/roadmap/15-address-intelligence` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/15-address-intelligence` / `ff82e26`.

Status: source complete; primary Mac build and native runtime acceptance pending.

Commit(s): `91501ab` (`implement address intelligence`).

Changed files and behavior:

- `astra/Models/Search/BrowserSearch.swift`, `BrowserSearchResult.swift`: one projection now backs New Tab and the address bar. It adds bookmark and same-Browser open-tab results. History URLs are grouped and ranked by match, frequency, and recency; ties and destination/type deduplication are deterministic. Open-tab selection revalidates the tab and URL, then selects that tab in the same Browser session. Only the typed address result calls `loadFromAddressBar`; history, bookmark, suggestion, and open-tab routes retain their existing load/selection behavior.
- `astra/Models/Core/Browser.swift`: query generations invalidate selection and pending OpenSearch results when text changes. Address-field query generation is isolated from new-tab query state. Normal and private Browser instances continue to own separate tab/history/bookmark/search state.
- `astra/UI/AddressBar/BrowserAddressField.swift`, `astra/UI/Content/NewTabView.swift`: address suggestions support arrow selection, Return, Escape, Tab completion, and per-URL history deletion. The native PasteButton reads only after explicit activation, accepts bounded HTTP(S) URLs, and never inspects the clipboard in the background. Result rows expose accessibility labels and identifiers.
- `astra/Models/Search/BrowserSearchSuggestions.swift`: suggestion request identity now includes query generation, provider, configuration, privacy and enabled state. Existing streaming byte limits, cancellation, and explicit private suggestion opt-in remain intact. An explicit “Discover search engine from this site” result fetches only HTTPS `/<opensearch.xml>` on the current site's host, caps the body at 64 KiB, and rejects cross-host/non-HTTPS final URLs.
- `astra/Models/Search/BrowserSearchMatching.swift`: a bounded native XML parser accepts only OpenSearch GET HTML templates with one `{searchTerms}` placeholder and passes them through the existing HTTPS custom-template validator. Discovery remains unavailable in private windows. The user must accept a confirmation before the existing portable `browserSearchConfiguration` setting changes; no setting key or config schema was added.
- `docs/astra-roadmap/checks/15-address-intelligence.swift`: standalone production checks cover result ranking/deduplication, selected-result resolution, query-generation/privacy request identity, the existing private-suggestion opt-in, and valid, invalid, insecure, and oversized OpenSearch data.

Acceptance cases satisfied, with evidence:

- Repeated history visits produce one URL result, with frequency and recency affecting rank. Same destinations remain distinct across result kinds. Stable ID tie-breaking makes equal-score results deterministic.
- The production check exercises ranked results, duplicate destination/type removal, explicit selection, and no automatic selection. The source guards New Tab and address results against query generation, current query, selected tab, and current search configuration changes.
- Normal autocomplete reads only the current normal Browser. Private results read only the current private Browser's in-memory data; remote private suggestions remain governed by packet14's off-by-default explicit opt-in. Discovery is disabled in private windows.
- Selecting an open-tab result verifies its tab and current active URL before selecting it. Deleting a history suggestion verifies that the same result is still present for the displayed query and removes history only; bookmarks remain.
- Clipboard access is limited to the native explicit PasteButton action. It accepts no more than 16 KiB and requires a valid HTTP(S) destination with a host.
- OpenSearch template parsing checks the root element, GET method, HTML result type, HTTPS template validity, exactly one searchTerms marker, a 2 KiB template ceiling, and a 64 KiB document ceiling. The write path requires a second explicit confirmation.

Checks run, scheme/destination/workspace and results:

- `swiftc -frontend -parse` over all changed production Swift sources — passed. This verifies parsing, not Xcode type checking.
- `swiftc -o /tmp/task15-address-intelligence-check astra/Models/Search/BrowserSearchConfiguration.swift astra/Models/Search/BrowserSearchMatching.swift astra/Models/Search/BrowserSearchResult.swift astra/Models/Search/BrowserSearchSuggestions.swift docs/astra-roadmap/checks/15-address-intelligence.swift && /tmp/task15-address-intelligence-check` — passed: `Task 15 address intelligence checks passed`.
- `git diff --check` — passed.
- No Xcode MCP workspace/build, app launch, hosted test, network discovery request, or runtime UI test ran. Primary owns the serialized Mac build.

Checks written but not executed: no additional checks.

Pending runtime/hardware/provider cases: Mac/iOS target type checking; native PasteButton appearance and paste permission behavior; address-field popup placement, keyboard selection, Tab completion, Return/Escape and VoiceOver; open-tab switching with hibernated tabs and active peeks; actual site availability/redirect behavior for `/opensearch.xml`; real OpenSearch provider templates; confirmation and portable-setting timestamp propagation. No browser or provider was contacted.

Migration, compatibility and private-data impact: no persistence or sync schema change. `browserSearchConfiguration` remains the existing timestamped portable setting and is updated only after user confirmation. No clipboard is read implicitly. Private tabs, history, bookmarks and queries are never projected into a normal Browser; remote private suggestions retain packet14's default-off behavior.

Capability gates / unresolved issues: discovery checks the conventional `/opensearch.xml` location only; it does not fetch a page to parse HTML `rel=search` links. This keeps discovery an explicit, bounded public metadata request and avoids credentialed page content. Site/provider availability and redirects need native runtime verification. A full Xcode build remains pending.

Merge prerequisites / follow-up ownership: primary source review and serialized Mac Xcode MCP build. Preserve packet14's suggestion-provider and private-opt-in rules, packet17's address prompt ownership, and packet29's timestamped portable-settings behavior. No defaults key, project file, controller/delegate file, sync schema, hosted test target, or server code changed.
