# Task 11: Favicons

Task / selected optional scope: `11-favicons`; baseline icon discovery, bounded origin cache, lazy refresh and deterministic UI fallback.
Branch / worktree / baseline commit: `astra/roadmap/11-favicons`; `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/11-favicons`; `42a1274`.
Status: source complete. Build remains pending because the Xcode slot is reserved for task 29.
Commit(s), or explicit uncommitted state: committed as recorded in the task branch.

Changed files and behavior:

- `astra/Storage/FaviconStore.swift`: selects the largest declared favicon, uses canonical page origins for cache association, refreshes unknown-age or seven-day-old entries on demand, checks request ownership after each await, bounds active requests to four, limits response bytes to 1 MB and each decoded frame to 512×512 across at most 32 frames, and trims persistent cache to 256 entries / 16 MB. Legacy host-only cache keys load as HTTPS origins. `clear()` invalidates pending work and persists an empty cache. Private stores continue to use an ephemeral URL session with no persistence service.
- `astra/Storage/FaviconKey.swift`: shared pure origin-key helper, including scheme, normalized host and non-default port.
- `checks/task11-favicon-key-check.swift`: runnable helper regression check.

Acceptance cases satisfied, with evidence:

- HTTP, HTTPS, default ports, non-default ports, host case normalization, and unsupported schemes are covered by the helper check.
- Different schemes and ports receive different icon associations. Cross-origin favicon URLs remain allowed as page metadata while results are committed only to the requesting page origin and current request generation.
- Persisted entries without stored fetch timestamps are treated as stale and refreshed at the next lazy load. Successful fetches remain fresh for seven days during the current process.
- Data, decoded dimensions, animation frame count, active fetch count and persistent-cache size are bounded in source.
- Tab rows and favourite tiles already use the same globe fallback; no UI edits were needed.
- Private results remain in the session-local in-memory dictionary. The private initializer has no persistence service and uses `URLSessionConfiguration.ephemeral`.

Checks run, scheme/destination/workspace and results:

- `swiftc astra/Storage/FaviconKey.swift checks/task11-favicon-key-check.swift -o /tmp/task11-favicon-key-check && /tmp/task11-favicon-key-check` passed.
- `git diff --check` passed.
- No Xcode build was run; task 29 owns the Xcode slot. No hosted tests or app runtime checks were run.

Checks written but not executed: no image-network fixture or platform image-decoding check was added; the pure origin helper check ran successfully.

Pending runtime/hardware cases: decode PNG, ICO, GIF and malformed images from real pages; verify icon selection, seven-day refresh and metadata mutation; delay responses across same-origin and cross-origin navigation, tab close and private-session disposal; check private requests leave neither disk cache nor normal cache state; clear website data during an active request; exercise cache eviction under actual persisted data.

Migration, compatibility and private-data impact: no persistence schema or portable sync payload changes. Host-only legacy entries are interpreted as HTTPS origins because old storage omitted scheme and port. Entries are local cache data and can be fetched again. Private session behavior remains isolated and ephemeral.

Capability gates / unresolved issues: build and platform decoding are pending. The existing `BrowserPersistence` file representation remains unchanged as required by ownership. Runtime isolation and network cancellation remain to be verified.

Merge prerequisites / follow-up ownership: reviewed baseline includes tasks 00, 01, 02 and 06. Task 04's full audit remains later in the queue; the source-established per-window session contract is preserved. Primary review is required before integration.
