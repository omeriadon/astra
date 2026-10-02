# 08 Windows and OS restoration

Task / selected optional scope: baseline normal-window restoration, per-window tab selection and geometry, close/reopen, screen sleep/wake and activation. Mini Astra remains transient and follows its explicit close/promote lifecycle. No optional OS feature was selected.

Branch / worktree / baseline commit: `astra/roadmap/08-windows-os-restoration` / `/Users/omeriadon/Documents/Xcode_App_Library/astra-worktrees/08-windows-os-restoration` / `b9ff0df`.

Status: source complete; production geometry/persistence check and source parse passed; serialized Xcode build pending with primary.

Commit(s): `73acd54` (the authorized packet09 duplicate-history notification correction cherry-pick); packet08 implementation checkpoint pending.

Changed files and behavior:

- `astra/Storage/BrowserPersistence.swift` adds optional window frame geometry to the existing local `BrowserWindowRecord`, validates finite bounded frames, clamps restored frames to a visible screen rectangle, and resolves a saved selection only when it still refers to an available tab. Window-record saves now replace the live record set so closed windows do not remain in the primary snapshot. The optional field decodes older records.
- `astra/Models/Core/Browser.swift` accepts a saved window identity/record, applies its valid per-window selection after disk or peer-placeholder hydration, and debounces geometry saves through the existing coalesced persistence path. The supplied record also preserves selection for same-process Dock reopen after its durable window record was removed. Geometry stays in `BrowserPersistedState`; `BrowserSyncDocument` and shared tab organization remain unchanged.
- `astra/Models/Core/BrowserWindowRegistry.swift` aggregates live normal-window records and temporarily retains not-yet-restored records while launch hydration constructs the remaining windows. Explicitly closed windows are removed from that pending set.
- `astra/App/AppDelegate.swift` loads saved records at launch, restores each normal window, queues HTTP(S) OS and Web Push URL opens until restoration completes, and queues Dock reopen during that interval. It flushes geometry before sleep/termination, reactivates the selected browser after wake, prevents overlapping termination prompts, and retains the last closed normal-window record in memory for Dock reopen. Private windows are not eligible for saved records or the reopen record.
- `astra/UI/Shell/BrowserWindowController.swift` restores the saved outer frame against its intersecting display or the main display, and saves outer geometry after move, resize, and fullscreen exit. It preserves the current fullscreen and page-controller instances. Close prompts are single-flight; approved close captures the frame before flushing persistence.
- `docs/astra-roadmap/checks-08-windows-os-restoration.swift` compiles the production persistence source with minimal model stubs and checks geometry clamping/idempotence, invalid geometry rejection, selection fallback, frame round-trip and closed-record removal.

Acceptance evidence:

- The geometry helper clamps an off-screen outer frame to the supplied visible bounds and produces the same geometry when clamped again. The AppKit controller converts restored outer frames back to content rectangles, avoiding repeated titlebar growth.
- Selection restoration uses a saved tab when present, falls back to the first surviving per-window tab, and returns no selection when none survive; Browser hydration then retains its global-selection fallback.
- Registry snapshots include normal windows only. Mini Astra is not registered; private windows are filtered. Geometry is encoded only in the local persisted state.
- Existing task02/task05 boundaries were inspected. AppDelegate handles external OS HTTP(S) URLs and does not duplicate popup or external-application policy. Startup queues preserve those original URL requests until the restored normal windows exist. WebKit popups and external schemes remain routed through BrowserController and its selected-controller/window prompt ownership checks. No BrowserController callback behavior changed.
- AppKit activation and sleep/wake hooks do not recreate controllers, stop media or alter PiP/capture state. Fullscreen geometry writes are skipped until exit.

Checks run:

- `swiftc -frontend -parse astra/App/AppDelegate.swift astra/UI/Shell/BrowserWindowController.swift astra/UI/Shell/MiniAstraWindowController.swift astra/Models/Core/BrowserWindowRegistry.swift astra/Models/Core/Browser.swift astra/Storage/BrowserPersistence.swift` — passed syntax parse.
- `swiftc -o /tmp/astra-windows-restoration-check astra/Storage/BrowserPersistence.swift docs/astra-roadmap/checks-08-windows-os-restoration.swift && /tmp/astra-windows-restoration-check` — passed.
- Xcode MCP build: pending primary serialization. No app launch, hosted tests, `xcodebuild`, formatter, or push was used.

Checks written but not executed: native tests require a macOS app session and actual AppKit windows; the standalone check exercises the production geometry/record/persistence code without AppKit runtime.

Pending runtime cases: restart with multiple normal windows and different selections; close then Dock reopen; canceled window close and canceled quit; multiple displays removed or resized/scaled; menubar/dock activation; fullscreen enter/exit; sleep/wake; logout/reboot; PiP and capture continuity across focus/fullscreen/wake; launch through an external URL while saved windows exist; first-startup blank/homepage behavior with multiple saved windows.

Migration, compatibility and private-data impact: `windowRecords` were optional in the existing version 3 envelope; adding an optional Codable frame preserves older records without an envelope-version change. Window geometry and selection remain device-local and are not added to portable sync. Private windows and Mini Astra remain outside durable window records. Per-window selected IDs resolve only against the restored shared tab set.

Capability gates / unresolved issues: source/build evidence does not establish AppKit notification timing, display-coordinate behavior at differing scale factors, or OS logout restoration. Dock reopen retains only the most recently closed normal window for the current process; the record is intentionally transient. External URL launch ordering is deferred until the asynchronous multi-window restoration completes and still needs runtime acceptance.

Merge prerequisites / follow-up ownership: primary source review and serialized Xcode MCP `astra` / `My Mac` build. Preserve the listed multi-display, fullscreen, sleep/wake, close/reopen and PiP/capture runtime cases. No push or original-checkout integration occurred.
