# Browser performance transfers — Build 3

Implements six source-audit candidates without changing the intended browser UI:

- Pinned folders expose headers/children as Sections in the outer LazyVStack. Expansion state belongs to the sidebar; rows retain UUID identity, indentation and the existing folder reorder collection.
- Sidebar projections include folder membership and cache split exclusions. No-split updates reuse base arrays; structural cache misses invalidate exclusions.
- History aggregation, locale-aware searchable text preparation and ranking run on a dedicated actor. Only four ranked value records return; result closures remain on MainActor. View tasks cancel on query changes/disappearance; revision/query matching prevents old rows from appearing, including after deletion. New-tab and address queries have separate publication state. Typed destinations/actions remain immediate; history appears asynchronously.
- Favicon callers share downloads by icon URL within their existing FaviconStore/session. Four distinct downloads remain the limit. Failures use a bounded 30-second retry cooldown; clear cancels requests and clears cooldowns. Each consumer still validates navigation, request and clear generations before committing. Equal bytes skip image decoding/publication/saving.
- Safari extension discovery shares an outstanding scan, caches discovery for 30 seconds, refilters current installations after awaiting, and avoids identical publications. The explicit Refresh button bypasses the time cache while joining a scan already running.
- Website-app icons load from a view task into a bounded cache. Installation version changes invalidate old icons; removal evicts entries while Settings is observing the registry. AppKit lookup stays on MainActor, outside row construction.

## Validation

The history Swift-model job compiles/runs a 10,000-visit parity fixture, duplicate URL aggregation, revision replacement, cancellation, and independent address/new-tab publication tests. Existing Observation, history-cache, extension hot-path/file-worker, WebKit resource and favicon observer guards are applicable.

This environment has no Swift/Xcode/macOS GUI. Native builds and the new executable test run through the PR workflows. No measured speedup is claimed. Remaining manual acceptance on macOS:

1. Expand a large pinned folder, scroll, rename/delete/reorder, collapse/re-expand and switch Spaces. Verify row appearance and drag targets.
2. Type quickly in both search surfaces; delete history during a query; verify ranking, keyboard selection, Enter and stale-result protection.
3. Open several tabs using one favicon, trigger a missing/invalid icon, retry after cooldown, and clear cached data while fetching. Check normal/private isolation.
4. Reopen/reactivate Extensions, explicitly Refresh, then install/remove an extension during a scan.
5. Edit a website-app name, change its icon, scroll its row offscreen/back, and uninstall. Confirm current icon and no lookup per keystroke.
