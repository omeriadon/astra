# Task 01 lifecycle handoff

Task / selected optional scope: 01-lifecycle; no optional scope selected.

Branch / worktree / baseline commit: `astra/roadmap/01-lifecycle`; `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/01-lifecycle`; `d1210af3ef5b73cd374ba9c8f30666f0267f9114`.

Status: build verified. Runtime acceptance remains pending.

Commit: this handoff is included in the bounded packet checkpoint. The primary's `docs/astra-roadmap/execution.md` update is included unchanged.

Changed files and behavior:

- `astra/Models/Core/Browser.swift`: promotion detaches the top peek without stopping its controller. Debug assertions check controller identity, WebView identity when already loaded, and unchanged navigation generation.
- `astra/Models/Tabs/BrowserTab.swift`: adds the non-destructive peek transfer operation and rebuilds peeks with the tab's existing session during initialization and wake.
- `astra/Models/Tabs/BrowserPeek.swift`: accepts the owning session when reconstructing a peek controller.
- `astra/Web/Navigation/BrowserController.swift`: makes `stopForClose()` idempotent; invalidates navigation/find work; cancels media, favicon, and preview tasks; invalidates KVO; detaches delegates, script handlers, WebView callbacks, and browser callbacks; rejects callbacks from invalidated or non-owned WebViews; guards delayed media, scroll, snapshot, download, and external-application work against close/navigation changes.
- `astra/App/AppDelegate.swift`: drops preview snapshots for selected and background tabs and peeks on memory pressure, without hibernating WebViews; cancels the pressure source at termination.
- `docs/astra-roadmap/execution.md`: primary-owned progress update, unchanged by this packet.

Acceptance cases satisfied, with evidence:

- Peek promotion preserves the transferred controller and, if loaded, its WebView. The navigation-generation assertion detects the previous teardown path, which retained object identity while invalidating the controller.
- Reconstructed peeks receive the parent's existing session, preserving private-session identity during hibernate/wake and normal shared-session behavior.
- Tab switching continues to render the tab's controller-owned WebView through `BrowserWebView`; no replacement-view logic was introduced.
- Closing/hibernating invalidates delayed work and releases owned preview snapshots. Memory pressure only drops previews and does not destroy page state.

Checks run, scheme/destination/workspace and results:

- Opened `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/01-lifecycle/astra.xcodeproj` with Xcode MCP; workspace `workspace-jHukLZKrOO`, scheme `astra`, destination `My Mac`.
- Xcode MCP `BuildProject` succeeded for the `astra` app target with no errors.
- `git diff --check` passed.
- No hosted tests or app runtime checks were run under the project restriction.

Checks written but not executed: no separate test harness exists after task 00 removed the missing test target. Compiled debug assertions cover peek promotion identity and navigation-generation preservation; dynamic execution remains pending.

Pending runtime/hardware cases: switch A→B and verify A's WebView identity; promote a loaded peek during playback and form entry; hibernate/wake normal and private tabs with nested peeks and verify URL/history/zoom/scroll/session isolation; exercise close and stale callbacks across redirects, history navigation, SPA URL changes, `about:blank` popups, and replacement documents; verify dirty input, loading, audio, camera, microphone, screen-only capture, and PiP under manual hibernation; apply memory pressure while the selected tab and peeks are visible. Native interaction-state restoration remains best effort with URL fallback. Do not use URL equality of `WKFrameInfo.request` as a document proof because hash and `history.pushState` changes retain the same document; exercise those cases explicitly.

Migration, compatibility and private-data impact: no schema or migration changes. Reconstructed peeks now use their parent tab's session. No private state is added to normal persistence or sync. Existing normal-window sharing and independent private sessions remain intact.

Capability gates / unresolved issues: camera/microphone state does not prove protection from screen-only capture. PiP remains unimplemented and unverified. Automatic hibernation remains disabled. Favicon task cancellation cannot guarantee an already-started `FaviconStore` operation will not populate its session cache; task 11 should add request-generation invalidation if close-time cache mutation must be prevented. Script messages have no stable public document token in the current bridge; delegate detachment and controller ownership prevent callbacks from a closed/replaced controller, while delayed same-WebView/document edge cases remain runtime checks.

Merge prerequisites / follow-up ownership: task 00 is present at the reviewed baseline. The primary reviews this packet before dependent work. PiP protection and screen-only capture capability remain with their assigned later packets.
