# 07 Tabs and spaces

Task / selected optional scope: baseline tab creation, duplication, close and reopen, MRU switching, tab and space ordering, pinned folders, and normal-window drag. No optional profile or independent window tabsets were added.

Branch / worktree / baseline commit: `astra/roadmap/07-tabs-spaces` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/07-tabs-spaces` / `d6be8c0f66d9aa5fbfcf270e6c2120ad7948dc05`.

Status: source complete and primary source-reviewed; app build gate remains open because the Xcode MCP transport closed before diagnostics or build could run. Source parsing and the focused production-model check passed.

Commit(s), or explicit uncommitted state: implementation source checkpoint `03da6a0a870011aeaaa3c3b12564b5d7427adfa3`.

Changed files and behavior:

- `astra/Models/Core/Browser.swift` validates tab destinations before removing old membership, ignores self-drops, and uses a monotonic destination clock so moves beat stale space/favourite/folder state. It updates folder clocks when memberships change, preserves folder members when deleting a space, stamps real space/folder edits, and repairs invalid close selections by choosing a remaining normal, pinned, or favourite tab before creating a blank tab. Duplicate tabs retain file-access bookmarks and are placed beside their source in its space, favourite, pinned and folder order. Tab switching follows the local recently-used order.
- `astra/Models/Spaces/BrowserWorkspace.swift` repairs duplicate, stale and conflicting memberships from persisted LWW clocks without changing clocks during reconciliation. It preserves stable order, assigns genuinely unowned tabs to the selected space, removes duplicate pins/folders/folder members, selects the freshest folder membership deterministically, and repairs stale per-space selection references. It also owns the tested MRU candidate and close-fallback selection rules.
- `astra/UI/Tabs/BrowserTabDragCoordinator.swift` records the source Browser weakly. A cross-window drop requires normal non-mini Browsers with the identical shared session, merges source state into the destination through the existing LWW peer path before moving, and selects the destination tab. It does not transfer a live WebView or controller. Private and Mini Astra drags are rejected.
- `docs/astra-roadmap/checks-07-tabs-spaces.swift` checks the production workspace reconciliation, MRU ordering and close fallback. It supplies small stand-ins for unrelated `BrowserTheme` and `OpenTab` dependencies so the actual `BrowserSpace` and `BrowserWorkspace` sources can compile standalone.

Acceptance cases satisfied, with evidence:

- Space membership, pins, folders and selections are normalized to unique live IDs. Conflicting space/favourite ownership uses the existing modification clocks and stable tie-breaks. The focused check covers stale/duplicate IDs, competing membership clocks, duplicate folder IDs, duplicate membership across folders and within a folder, unassigned-tab placement, selected-tab repair, and unchanged space modification time during repair.
- Moving a tab validates the destination before mutation. Moves update every affected space and folder clock, and give the destination a later timestamp than the previous owner. Folder moves reject missing destinations and self-targets without mutation.
- Closing a normal tab selects the previous normal tab, then another visible pinned/favourite tab if the normal space would become empty; a new blank is added only when no visible tab remains. Bulk-close selection is validated after removal.
- Reopen continues to use the existing closed snapshot, space ID and normal index. Duplicate placement preserves URL/title/history/zoom/peeks, its local file-access bookmark and source organization.
- Candidate switching follows current-window MRU. MRU remains transient, matching the existing window-local state; the selected tab and tab order remain in existing persisted snapshot/workspace fields.
- Normal-window drag uses replicated per-window tab/controller state and the existing peer LWW merge. It rejects private and mini windows and mismatched sessions.

Checks run:

- `swiftc -o /tmp/astra-tabs-spaces-check astra/Models/Spaces/BrowserSpace.swift astra/Models/Spaces/BrowserWorkspace.swift docs/astra-roadmap/checks-07-tabs-spaces.swift && /tmp/astra-tabs-spaces-check` — passed.
- `swiftc -frontend -parse astra/Models/Core/Browser.swift astra/Models/Spaces/BrowserWorkspace.swift astra/UI/Tabs/BrowserTabDragCoordinator.swift` — passed syntax parsing; this is not a typecheck.
- `git diff --check` — passed.
- Xcode MCP diagnostics/build — not run. The MCP transport closed while the primary opened the 07 workspace; the primary instructed that no further build attempts be made until the external tool state changes. No `xcodebuild` command was used.

Checks written but not executed: no additional runnable checks. The app-level organization/drag paths were not executable under the available source/build-only workflow.

Pending runtime/hardware/provider cases: exercise close and reopen UI, keyboard switching and focus, pinned/favourite behavior, duplicate placement, within-space/folder reorder, cross-window drops during peer latency, drag cancellation and window closure, restoration of order/selection, and controller/peek/session continuity in the running app.

Migration, compatibility and private-data impact: no schema or persistence-format change. Existing per-space/favourite modification times, workspace selection metadata, OpenTab closed-space/index metadata and BrowserWindowRecord selection continue to carry persisted state. No MRU field was added. Private sessions remain isolated and cannot be moved through the tab organization or cross-window drag paths.

Capability gates / unresolved issues: the standalone check does not compile `Browser.swift` or the macOS drag coordinator. The app build remains an explicit compile gate. No app launch, hosted test execution, runtime drag, cross-window controller test or private-session UI test was performed.

Merge prerequisites / follow-up ownership: serialized Xcode MCP `astra` / `My Mac` build when the MCP transport is available. Preserve this worktree and branch; no push, merge or original-checkout edit occurred.
