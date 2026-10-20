# Astra rendering CPU investigation — 2026-10-14

Status: investigation report with native Release recordings, a controlled minimal reproduction, source audit, and tested visibility predicate. Production remediation and the full runtime state matrix remain unverified.

## Scope and provenance

Investigate repeated SwiftUI/AppKit rendering, attribute update owners and invalidation sources, and recommend changes that preserve active appearance and interaction. Production changes, sync remediation, dependency upgrades, and visual simplification are outside this investigation.

Acceptance requires a reproducible association between window state, state writes, view updates and CPU; a clean Debug/Release comparison; and matched before/after evidence for any experimental fix. Unmeasured findings remain hypotheses.

The supplied specification is `Pasted text(20261014-021453).txt`. The Terminal transcript is `Pasted text(20261014-080853).txt`; table-of-contents exports are `Pasted text(20261014-115326).txt`. The two outer trace archives contain the same-named, same-size inner ZIP (78,420,294 bytes); their bytes have not been compared. `exported-tables.zip` contains seven XML tables, approximately 1.014 GB uncompressed. Analysis must resolve Instruments' table-local ID/reference encoding rather than count only explicit text nodes.

The user's capture identified source revision `7d26bb70657b1d0b3a1154bce2f76612bb0cb1cb`. The present source audit uses `9f13417bcfba2b4d32ddb33acb426781e865028a`, isolated in branch `investigation/swiftui-cpu-20261014` and sibling worktree `astra-swiftui-cpu`. These revisions must not be treated as equivalent. A scoped revision diff shows that artwork, mirror, hover, window-controller and BrowserController files are unchanged between these revisions; Browser and several Settings/content files changed. The original working directory has existing project and scheme-management changes; neither is modified here.

## Capture validity

| Capture | Duration | End condition | Interpretation |
| --- | ---: | --- | --- |
| hidden-cpu.trace | 0.917036 s | User pressed Stop | Too short to establish sustained idle CPU or periodic tasks |
| hidden-swiftui.trace | 20.708316 s | Time limit reached | View-update evidence, with substantial tracing/debugging configuration concerns |

Both attached to Astra PID 28760. Metadata identifies macOS 27.2 (26B5112a), Xcode/Instruments 27.2 (27B5028f), ARM64 MacBook Air, 16 GiB memory. The executable is in `Build/Products/Release`. The process environment also has `MTL_DEBUG_LAYER=1`, `SWIFTUI_VIEW_DEBUG=287`, and injected Xcode log redirection, main-thread checker, view-debugger support, and GPU capture libraries. This confirms a Release executable launched with diagnostics, not an ordinary detached Release baseline. It does not prove that the debugger remained attached throughout recording.

The Terminal transcript contains a large AttributeGraph tree dump. This is additional evidence of diagnostic activity; its cost requires attribution in the samples. The SwiftUI cause export includes a notification path through `NSWindow.becomeKeyWindow` around 6.986 s. Becoming key is a lifecycle event, not proof that the entire interval was visibly foregrounded. No synchronized occlusion/app-hidden timeline was supplied. Archive names and instructions alone cannot establish continuous hidden state.

Recorded CPU under SwiftUI tracing must not be presented as uninstrumented idle CPU. Per-view durations can nest and overlap; summing them is not a CPU breakdown. Sampled stack inclusive weights likewise overlap. WebKit child-process CPU is not attributable from the Astra-only attached-process tables.

## Confirmed native rendering hotspot

**The media-card waveform symbol effect is a confirmed source of sustained hidden-window rendering work.** Its owner is `astra/UI/Chrome/BrowserMediaActivityView.swift`, `BrowserMediaActivityCard.body`, line 52:

```swift
.symbolEffect(.variableColor, isActive: controller.isPlayingMedia && !reduceMotion)
```

The condition stays true while media plays even when the window is hidden. There is no window-observability gate. The SF Symbol effect schedules rendering with otherwise fixed input; a 60 Hz application `body` loop is not required. The associated AppKit layout, flex/glow and spring stacks reproduce in a standalone card with no WebKit, audio, networking, polling, or repeated model writes.

### Archive and independent launch

Xcode MCP successfully built the isolated revision using `astra Performance` (Release, optimized ARM64). Xcode's native Product > Archive action also succeeded. Archive:

`/Users/omeriadon/Library/Developer/Xcode/Archives/2026-10-14/astra Performance 14-10-2026, 10.11 PM.xcarchive`

Profiled application:

`Products/Applications/astra.app`

The archived process was PID 80552, parent launchd, launched independently of Xcode through LaunchServices. TOC environment metadata contains none of `DYLD_INSERT_LIBRARIES`, `SWIFTUI_VIEW_DEBUG`, or `MTL_DEBUG_LAYER`. The CPU recordings use Time Profiler alone, not the SwiftUI template. Builds had finished before these four valid comparison captures. Low Power Mode remained off; no power or accessibility preferences were changed.

### Controlled results

| Scenario | Covered CPU-table interval | CPU seconds | Mean CPU, one-core basis | Main-thread CPU seconds |
| --- | ---: | ---: | ---: | ---: |
| Archived Astra, static local page, hidden | 30.337 s | 0.065 | **0.214%** | 0.022 |
| Minimal static media card, hidden | 16.279 s | 0.016 | **0.098%** | 0.009 |
| Same minimal card, waveform effect active, hidden | 20.321 s | 3.809 | **18.744%** | 3.445 |
| Archived Astra, silent media fixture with active media chrome, hidden | 30.305 s | 9.735 | **32.124%** | 8.284 |

In the paired minimal test, only enabling the waveform effect changes continuous behavior. The fixed mode caption also changes once; it does not schedule repeated work. Both captures use the same process, PID 81411. Approximately 90.4% of the waveform probe's sampled CPU is on main; Astra's active-media recording is 85.1% main. The static probe's near-zero result rules out the static glass card and its controls as sufficient to produce this specific sustained cost.

After excluding the first two seconds of each covered CPU-table interval, means are 0.198% for quiet archived Astra, 0.070% for the static probe, 18.918% for the waveform probe, and 32.316% for Astra with media chrome. The animated cost persists beyond setup. These are single runs, not statistical confidence intervals. Comparing means is necessary because exported coverage differs. Do not advertise the CPU-seconds ratio as a whole-app speedup: the two probe recordings have different durations, and the quiet Astra case does not include active media.

The waveform probe has 0.197 s of inclusive sampled weight containing `FlexCoreInteractionModifier.FlexValue` and 0.043 s containing `FluidSpringAnimation`. Astra's media capture has 1.082 s and 0.313 s respectively. Those patterns are overlapping subpaths, not the entire CPU cost; the surrounding layout/display pipeline also consumes work. No SwiftUITracingSupport involvement is identified in these CPU-only comparison captures. Literal `symbolEffect` function names need not appear in optimized framework stacks: causality here comes from the controlled code change, supported by the matched stack mechanism.

### Visibility evidence and timing

The initial tool observation recorded probe `NSApplicationDidHideNotification` at 22:20:15.166, with `appHidden=true`. The static capture ran 22:20:26.745–22:20:47.614. The waveform mode was selected at 22:21:25.372 while the probe remained hidden; that capture ran 22:21:42.521–22:22:03.272. A later unhide event at 22:22:48.539 occurs after both recordings. The early info-level hide event was visible in the initial log query but is absent from the later retained log, so it is explicitly transcript evidence rather than a claim of a complete durable lifecycle log.

Astra was hidden through Command-H after the static fixture loaded, then again after starting the silent media fixture. Its media capture ran 22:24:05.284–22:24:36.039. The fixture uses looping silent PCM with a normal non-muted media element: the controller's audibility classifier tests playback/mute/volume state rather than actual PCM amplitude. This activates the media chrome without audible test noise. The local page contains no visual animation. Actual HTML media playback and WebKit are present in the Astra arm, so the exact portion eliminated by a production gate still needs an in-app before/after test. The standalone paired test isolates the rendering trigger independently of that media work.

### Targeted fix and expected benefit

Keep media playback, capture protection, progress, and all active visuals unchanged. Add window-local render eligibility to the waveform effect:

```swift
.symbolEffect(
    .variableColor,
    isActive: controller.isPlayingMedia && !reduceMotion && windowCanRender
)
```

Eligibility is `!NSApp.isHidden && window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)`. Application activation is deliberately excluded: a visible background window should keep its waveform. Resolve the actual hosting window when its native view attaches; subscribe to that window's occlusion/minimization changes and app hide/unhide; publish only when the eligibility Boolean changes; remove observers on teardown. A window reader that checks only its initial nil window is incorrect and can permanently disable visible animation. The probe contains a `viewDidMoveToWindow` bridge specifically to avoid that attachment race.

Expected benefit: eliminate the waveform's unnecessary visual scheduling while unobservable. Confidence is high for this trigger and the need for lifecycle gating, based on the paired minimal test. **No percentage improvement for a patched Astra binary is claimed**, because no production fix has been applied. Foreground waveform appearance uses the same effect and input when eligibility is true; native reveal/phase continuity still requires runtime verification.

`checks/GlassIdleProbe/` contains the reproducer, a visibility-gated comparison mode, and a standalone self-check covering all 16 visibility combinations and valid initial modes. The current probe adds visibility tracking and an explicit AppKit host after the original paired capture; the measured pair used the earlier WindowGroup host. Current sources compile under Swift 6 with optimization, and the predicate self-check passes. The new gated mode itself has **not** been performance validated. Additional CLI launch experiments did not verify that the intended view tree was mounted, so they are excluded from quantitative conclusions.

### Remaining native verification and cleanup limits

Computer Use began returning `cgWindowNotFound` for Astra, Finder, the probe, and fresh bindings. Refreshing inventory and resetting the control session did not restore window access. A ScreenSaver process appeared during this period; that correlation does not establish the server error's cause. No screen-lock or security protection was bypassed.

Consequently, native tests of minimize/Space switches/full occlusion/multiple windows/Low Power Mode/About artwork/hover/popover/reveal and the exact in-app gate remain unmeasured. The actual Astra pause-versus-playing comparison was interrupted before the pause action could execute. The report's full scenario matrix below is a reproducible remaining protocol, not a list of passed tests. No detached Debug runtime comparison or foreground frame-latency benchmark is available.

The owned probe process, diagnostic log stream and fixture server were stopped. Two temporary localhost profiling tabs remain in Astra because native cleanup controls were unavailable; the media tab may continue its silent loop from WebKit's cached asset. Existing user tabs were not deleted or force-closed. This remaining state must not be mistaken for the quiet baseline.

Raw recordings and named XML exports are in `/Users/omeriadon/Desktop/astra-render-investigation-20261014`. The consolidated numerical evidence is `docs/performance/2026-10-14-render-runtime-summary.json`. The archived application and all production source remain unchanged by this investigation. No full-app CPU, energy, or frame-pacing improvement is claimed until the lifecycle gate is implemented and measured.

## Earlier supplied capture: measured breakdown and confounders

The earlier supplied SwiftUI capture has substantial tracing activity and intermittent CPU bursts. It does **not** by itself establish sustained high CPU in a clean, continuously hidden Release process. The native experiments above confirm a current rendering hotspot, but do not assign all of the original Debug regression to that hotspot. Source analysis also identifies additional visibility/lifecycle gaps whose costs remain unmeasured.

The short standalone Time Profiler capture is insufficient. The usable exported CPU table covers 0.980–20.708316087 s, matching the longer SwiftUI recording's endpoint. Its 1,973 intervals integrate to **3.9084 CPU seconds**, averaging **19.811% of one core** over 19.728316087 s. The time-profile export's 39,084 samples carry the same total weight, 3.9084 s; this is a useful cross-check, not an independent uninstrumented run.

| Thread group | Integrated CPU seconds | Share of recorded CPU | Mean one-core percentage over covered interval |
| --- | ---: | ---: | ---: |
| Main thread, 0x834db | 1.5969 | 40.86% | 8.09% |
| Worker thread, 0xa4d75 | 1.8068 | 46.23% | 9.16% |
| All other threads | 0.5047 | 12.91% | 2.56% |
| Total | 3.9084 | 100% | 19.81% |

The worker's name alone does not identify its subsystem. Stack attribution, not the thread name, is required. One-second CPU bins vary sharply: 96.58% during 1–2 s, 93.18% during 2–3 s, then 0.4%, 0.35%, and 0.3% during 3–6 s; the 7–8 s bin rises to 44.02%. This is not uniform continuous high CPU. Attachment/diagnostic work and lifecycle transitions are confounders; a quiet short interval also cannot prove prolonged idle is healthy.

Ranked **recorded stack involvement**, not an additive cost partition:

| Stack path or binary | Inclusive sampled weight | Share of sample weight | Evidence classification |
| --- | ---: | ---: | --- |
| SwiftUICore present | 2.4036 s | 61.50% | Framework mechanism confirmed; includes callers/tracing, not exclusive rendering cost |
| SwiftUITracingSupport present | 1.9531 s | 49.97% | Profiling involvement confirmed; ordinary CPU cannot be inferred from this observer-heavy run |
| `specialized Trace.add<A>(handle:)` | 1.7147 s | 43.87% | Trace-collection path confirmed |
| AttributeGraph present | 1.8199 s | 46.56% | Graph work confirmed, overlaps tracing and rendering |
| Astra binary present | 1.5604 s | 39.92% | Includes ancestral application entry points; not exclusive Astra computation |
| QuartzCore present | 0.8362 s | 21.40% | Transaction/compositing mechanism confirmed, application owner unresolved |
| WebKit present in Astra stacks | 0.3664 s | 9.37% | In-process involvement only; child-process CPU not captured |

The largest named leaf is Swift protocol-conformance lookup at 0.7805 s (19.97% of sample weight). Demangling and tracing are also present. Attribution to tracing for every protocol-conformance sample has not been computed, so that leaf is not automatically all profiler overhead. Symbols marked `<deduplicated_symbol>` limit exact symbol resolution. Binary/symbol inclusive totals count each entity at most once per sample; shares **overlap** and must never be summed into a subsystem total.

### View counts and timing alignment

SwiftUI updates cover 6.985766083–26.528404958 s, extending **5.820089 s beyond the CPU table**. Cause/change/group tables also extend beyond CPU recording. Their events may reflect tracing drain/teardown or a different export timing scope; the cause of the extension is unverified. They cannot all be paired with the recorded CPU. The strongest update-count burst at 22–23 s lies outside CPU coverage.

Across the entire exported SwiftUI update window: 140,042 events comprise 132,518 Other Updates, 6,600 View Body Updates, and 924 Representable Updates. Only 1,786 events are labeled module `astra`; 1,059 of those start inside the CPU window. Framework body updates and all graph updates must not be described as Astra body evaluations or rendered frames. There are 36,588 update events in the 7–8 s bin and 36,523 in the 22–23 s bin; these are graph-event bursts, not 36,000 frames per second.

| Application owner/type | Entire exported window count | Count starting within CPU coverage | Interpretation |
| --- | ---: | ---: | --- |
| BrowserRootView body | 10 | 4 | No demonstrated 60 Hz root body loop |
| DesktopBrowserShell body | 10 | 4 | No demonstrated 60 Hz shell body loop |
| ShellSidebarListView body | 8 | 4 | Parent projection work is not demonstrated to run continuously |
| BrowserTabRow body, all instances | 127 | 0 | All recorded row body events here are outside CPU coverage; do not use 127 to explain this CPU |
| BrowserAddressField body | 29 | 8 | Focus/address owner active; specific state-write attribution unresolved |
| BrowserLoadingBar body | 27 | 17 | Loading/progress events require controlled loading-to-idle experiment |
| MiniAstraView body | 8 | 7 | A Mini view is represented in the export; visibility/number of Mini panels unknown |
| BrowserDropZone Other Updates | 356 | 230 | Native drop/graph events, not body evaluations |
| BrowserDropZone Representable Updates | 73 | 48 | Candidate bridge seam; measured cost and causal owner still needed |
| WindowFocusReader Representable Updates | 19 | 15 | Bridge updates exist; source only calls onWindow when moved to a window |

Counts combine instances of each named view. Aggregate counts cannot establish a single view's per-frame rate. The CPU-aligned portion of SwiftUI export begins at roughly 6.986 s, so it does not cover all CPU samples from 0.980 s. Repeating artwork/mirror views are not identified in the app-owned update list; this does not exclude them, because instantiated/compositor work need not produce app body events and the export may be selective.

The change export contains 2,751 `External: PlatformGlassInteractionState` events and 1,641 `Layout: AnimatableFrameAttribute` events. The update table names `FlexCoreInteractionModifier` 6,223 times. This confirms interaction/layout machinery in the exported interval; it does not identify an address field, favourite tile or artwork star as the expensive owner. Cause-edge labels are summarized separately from change-event descriptions. The analyzer does not yet traverse the complete cause graph into a verified application property-write chain.

### Verification and limits

The full seven-table archive was parsed successfully after reference and stack-attribution corrections. The analyzer fixture passes nanosecond conversion, interval integration, reference reuse, leaf/inclusive binary attribution and unresolved-reference rejection. Process and summed thread CPU agree within floating-point rounding. App-labeled totals match the module count. No compilation or runtime benchmark is implied by these offline checks.

Evidence files: `2026-10-14-render-trace-summary.json`, `scripts/analyze_render_trace.py`, `checks/render-trace-analysis-check.py`. The analyzer is designed for these exported schemas, not a universal Instruments importer; inclusive update durations remain explicit. No before/after fix experiment has run, no confidence interval is available from a single capture, and foreground responsiveness, energy, GPU/compositor load, clean Release CPU and exact hidden state remain unmeasured.

## Source ownership and lifecycle audit

Source references below refer to the isolated audit revision. A source-confirmed scheduling path is not a confirmed high-cost runtime hotspot.

| Area | Exact owner | Initiator and stop condition | Finding and confidence |
| --- | --- | --- | --- |
| Root window | `UI/Content/BrowserRootView.swift`, `BrowserRootView.body` | Model/Defaults/environment changes; key-window notification | Reads specific observable values, not a blanket object publication. Duplicate activation paths are guarded by `BrowserWindowRegistry.activate`. No unconditional root render timer identified |
| Window occlusion | `UI/Shell/BrowserWindowController.swift`, `windowDidChangeOcclusionState` | AppKit delegate notification | Calls benchmark logging only. Does not publish visibility to visual task owners. Source-confirmed absence of lifecycle propagation in this delegate |
| Hosting/layout | `UI/Shell/BrowserContentHostView.swift`, initializer | Four edge constraints around one host | No custom repeated layout scheduling here; framework layout stacks alone cannot implicate this wrapper |
| Sidebar projection | `UI/Shell/BrowserSidebarControls.swift`, `ShellSidebarListView.body`, `SidebarProjectionCache.resolve` | Structural/tab-collection revisions, selected state | Existing structural cache, lazy grid/stack, stable tab IDs, precomputed indices and ownership set. Do not reimplement these optimizations. Split exclusion still filters arrays on parent evaluation; cost unmeasured |
| Sidebar native reorder | Same file, `reorderable`/`reorderContainer` composition | SwiftUI native reorder/layout machinery | Export contains reorder/anchor/opacity nodes. Their presence does not prove a reorder loop. Need event rates and causal state writes |
| Tab rows/tiles | `UI/Tabs/BrowserTabRow.swift`, `BrowserFavouriteTile.swift` | Selected/hovered/tab state; geometry only while hovering for preview anchor | Existing Equatable boundaries and scoped geometry. Row split-drop width observation is still mounted. Equatable does not suppress independently observed property/environment updates |
| Navigation/address | `UI/Chrome/BrowserNavigationControls.swift`, `UI/AddressBar/BrowserAddressField.swift` | Navigation, loading, zoom, focus, address state | Small navigation subviews; history-array `.id` rebuild already removed. Address has explicit interactive glass. Bordered system controls can also contribute framework interaction work; explicit `.interactive()` sites are not an exhaustive owner list |
| Loading | `UI/Chrome/BrowserLoadingBar.swift`, `loadingDidChange` | Loading/progress changes; completion hides the bar | Finite 0.2 s progress/completion and 0.1 s hide; generation prevents stale completion. No idle repeating animation identified |
| About/Update artwork | `UI/Settings/Detail/Update/BrowserUpdateArtwork.swift`, `AboutArtworkStar`, `AboutArtworkDustStar`, five GlassStar `onAppear` handlers | Appearance sets pulsing; seven `repeatForever` sites | No explicit occlusion/hide/minimization stop. Some opacity repetition remains despite Reduce Motion. No Low Power Mode policy. High-confidence lifecycle gap; execution and CPU cost while hidden unverified |
| Artwork AppKit bridge | Same file, `GlassStar.updateNSView` | Every representable update assigns new `GlassStarContent` to nested `NSHostingView.rootView` | Continuous animated geometry plus nested hosting/interactive glass is an isolation candidate. Do not assume root assignment occurs every animation frame; measure representable update and layout counts |
| Window mirror | `UI/Content/BrowserTabMirrorView.swift`, `.task(id: controller.id)`; `Web/Navigation/BrowserController.swift`, `refreshWindowMirrorSnapshot` | Mounted duplicate-window mirror starts immediate snapshot; sleeps 1 s; task cancellation stops | No destination-window visibility check. Snapshot checks source WebView `isHidden`, ownership and generation, not window occlusion. A hidden window can remain mounted. Source-confirmed opportunity, unknown measured cost |
| Selected-page preview | `BrowserController.startPreviewSnapshotRefresh` | Created page starts loop; 50–58 s sleep; invalidation cancels; background tab flag suppresses request | Selected-tab flag is not actual window visibility. Hidden selected page can remain eligible. Cannot establish cadence from a 20 s capture |
| Hover preview | `BrowserTabHoverPreviewCoordinator.hoverBegan/hoverEnded/dismiss`; `BrowserTabHoverPreviewCard.body` in `BrowserTabRow.swift` | 1 s cold/250 ms warm debounce; 160 ms dismissal; mounted card samples memory every 2 s | Normal pointer exit cancels activation/removes card. Sidebar exit, drag and library presentation dismiss it. No explicit hidden/occluded event dismissal in the inspected window delegate; test hover then hide, especially missed hover-ended events |
| AI link popover | `UI/Chrome/BrowserAIHoverPreview.swift`, `requestKey`, `startPreview`, `dismiss` | Hover/navigation/settings key; dismiss on disappearance/explicit dismissal | Key includes link rectangle and settings. Geometry changes may restart requests; no idle timer identified. Preserve entering-popover behavior during cancellation work |
| Haze/material | `UI/Shell/topVariableBlur.swift`; `UI/Background/BrowserThemeBackground.swift` | Geometry/appearance/power changes; backdrop rendering owned by frameworks/dependencies | Equatable gradient, edge-only Haze overlays, empty material `updateNSView`. Low Power Mode removes compositing group but uses the same Haze radii; comment claiming half strength is not reflected in different radius inputs. GPU/compositor cost unmeasured |
| Gradient/noise | `ThemeSurface`, `MeshGradientSurface.colors(for:)`, `StableRandomNoise.ensureTextureCovers` | Theme/size changes | Mesh color generation does 100 weighted point interpolations per initializer. No animation timeline in this code. Noise is conditional and backing size quantized. No evidence for continuous noise generation at idle; dependency internals not inspected |
| Space transitions | `DesktopBrowserShell.swift`, `ShellSpaceTabList`, `ShellContentColumn`; `BrowserPageView` | Space change; 100 ms fade, 105 ms delayed swap, 100 ms fade | Finite animations with generation checks. Space `.id` replaces tree deliberately; not an unconditional identity churn |
| Native space pager | `UI/Shell/BrowserSpacePager.swift`, `startSettling`, `step`, `stopSettling` | Settling allocates display link; tolerance/dismantle invalidates | Not the active desktop composition here. Do not attribute active sidebar CPU to its CADisplayLink merely because the file exists |
| Downloads/library | `BrowserDownloadsBarView`, `LibrarySidebarView`, `BrowserDownloadManager.updateProgress/computedChromeSummary` | Download progress, selection and library mount | Aggregates cached by item revision; progress publication is coalesced and one array mutation. Aggregate getter still observes full items, so historical/download metadata mutations may invalidate chrome. Trace must demonstrate a meaningful rate before decomposing state |
| Download flight | `DesktopBrowserShell.body`, flight task | New download animates 0.7 s; task clears after 750 ms | Finite, cancellation checked. No perpetual flight identified |
| WebKit bridge | `Web/Navigation/BrowserWebView.swift`, `BrowserWebViewHost.layout/mountIfReady` | Layout and specification changes | Existing frame, visibility and inset equality guards. Handoff snapshot retry is bounded to 1 s at 75 ms cadence, cancelled on dismantle. Attachment and selected-tab visibility are different from actual occlusion |
| Media fallback | `BrowserController.startMediaObservation` | Created WebView; loops every 5 s active media/capture, 20 s selected attached idle, 90 s detached/background | Attached hidden selected pages still use 20 s cadence. Media/capture protections are intentional and must survive any visual-task visibility gate |
| Media waveform | `UI/Chrome/BrowserMediaActivityView.swift`, `BrowserMediaActivityCard.body` | Playing media enables `.symbolEffect(.variableColor)`; stops when playing becomes false or Reduce Motion is true | **Confirmed sustained hidden rendering trigger** in the controlled probe and active Astra media scenario. Window hide/occlusion is missing from eligibility. Only the visual effect should pause; playback and capture protection must continue |
| Mini Astra | `MiniAstraView`, `MiniAstraWindowController.windowWillClose`, `MiniAstraOpeningAnimation.show` | Explicit show; opening animation 250 ms; close stops controllers | Resign-key changes floating level, not task visibility. Hidden panel remains different from closed/promoted panel. Promotion detaches content; confirm retained controller teardown during runtime |
| Traffic lights | `BrowserWindowTrafficLightAnimator.setHidden` | Chrome visibility change; 200 ms finite animation | Target/generation guards and blur cleanup exist. Uses `window.isVisible`, not occlusion, to select animation. No self-restarting loop found |
| Quit banner | `BrowserRootView.swift`, `BrowserQuitFeedback`, `QuitBannerOverlay` | Quit gesture mounts `.animation` TimelineView; expiry task removes after roughly 1 s | Unnecessary frame cadence for a boolean expiry is possible, but bounded and event-specific. Cannot explain prolonged hidden idle without repeated quit triggers |
| Main-thread watchdog | `App/BrowserLog.swift`, `bootstrap/startMainThreadWatchdog/watchdogTick` | Process startup; 250 ms Debug timer, 1 s Release timer, always queues main acknowledgement | Source-confirmed periodic wakeups even with verbose logging disabled. It does not mutate observable view state; do not infer a render loop from its main-queue acknowledgement. CPU/energy cost requires measurement |

Local Haze implementation review: `Packages/Haze/Sources/Haze/HazeEffectView.swift` guards mask rendering on dirty state or changed bounds, reuses a CIContext, and configures the backdrop layer with `disablesOccludedBackdropBlurs=true`. This makes an unconditional Haze mask-regeneration loop less plausible at constant inputs. The private layer flag does not prove that all compositing work stops under occlusion; GPU/window-server measurement is still needed.

The resolved Noise 2.0.5 dependency has an animation TimelineView only when speed/time is nonzero. Astra constructs `Noise(style: .random)` with the default zero speed, so that call uses the static shader branch. Installed DisplayLink has no active direct call site in this desktop composition apart from the separate inactive pager implementation. MaterialView's inspected source uses layout/appearance notifications rather than a discovered repeating timer. These source findings narrow candidates; they are not GPU timing measurements.

## Original Debug sample recovered from Desktop

`astra-cpu-sample.txt` identifies Debug Astra PID 38267 with parent `debugserver`, sampled at 09:36:25 on the same macOS build. The accompanying `astra-cpu-20261014-093705/processes.txt` lists Astra at 58.6% CPU and one WebContent process at 6.4%. These are process snapshots, not a time-integrated CPU breakdown or proof of WebContent ownership.

The sample contains the original AppKit layout/SwiftUI flex/glow/spring stacks and the old BrowserSync URL/CharacterSet-validation path. Thus the earlier high CPU report has supporting evidence; the observer-heavy later Release recording does not erase it. The sample also includes waiting threads. Its node counts must not be converted directly into one-core CPU percentages, and its revision/visibility are not recorded precisely enough for a matched comparison with the current build.

## Flex/glow attribution and falsifiable hypotheses

Explicit interactive glass occurs in favourite tiles, address field, Peek controls, theme editor/pickers, screenshot controls, and artwork GlassStars. Native glass/bordered controls add other possible owners. The supplied system symbols identify mechanism, not application ownership.

The paired native waveform experiment now resolves an additional hypothesis: enabling only the fixed card's variable-color symbol effect produces sustained hidden CPU and flex/spring stacks. The hypotheses below concern other paths and the earlier supplied recording:

1. **Profiler/diagnostic amplification.** If tracing and debug overlays dominate the supplied CPU, a detached Release run under Time Profiler alone should show much lower CPU and no sustained SwiftUITracingSupport work. This would qualify this recording, not disprove the original Debug symptom.
2. **Artwork keeps animation scheduling alive.** With identical settings/theme, hiding an About/Update window should retain animation/flex updates; temporarily pausing only its repetitions while hidden should suppress those updates and preserve visible appearance after reveal.
3. **Hidden duplicate mirror performs unnecessary snapshots.** With the same tab selected in two windows, hiding only the mirror destination should leave one-second snapshot calls; a destination visibility gate should remove them without preventing visible-mirror updates.
4. **Window focus/layout transitions are misclassified as idle.** If the spike clusters around key-window and layout events then a settled, continuously hidden interval should lose that spike. Correlate counters and notification timestamps rather than infer from filename.
5. **State propagation repeatedly rebuilds sidebar/layout.** A specific state-property cause must precede repeated sidebar/reorder updates. If no such write is present, refactoring global state is not justified.

The standalone hidden-card experiment now provides a minimal reproduction of expensive platform rendering with constant application inputs. Whether this represents a macOS 27.2 beta regression versus expected framework behavior requires the same probe on another OS build. The safe app workaround is visual lifecycle gating; no unsupported Apple-framework fix or permanent effect removal is proposed.

## Exact implementation recommendations, conditional on measurement

Priority 0: retain the clean Release baseline and capture provenance above. Extend synchronized visibility records and replicate the controlled cases. Keep the original captured revision and current revision in separate result labels; establish whether sync remediation is already included. Use a quiet website without video, loading or active downloads for the quiet arm. Preserve user data and all UI effects.

Priority 1, confirmed: gate only the media waveform symbol effect by the actual hosting window's render eligibility, as specified above. Reuse the project's native window attachment pattern, observe the relevant window/app lifecycle, and avoid unrelated observation/cache refactors. Compile Debug and Release through Xcode MCP, then compare the same playing-media card before and after while hidden, minimized and occluded. Verify the still-visible inactive-window positive case and resume on reveal. Keep the audio playing throughout the visual comparison. The minimal probe establishes the potential benefit; exact app savings remain unmeasured.

Priority 1: if artwork is active while unobservable, propagate window-local render visibility to artwork. Eligibility should consider app hidden state, destination window visibility, miniaturization and `.occlusionState.contains(.visible)`; app inactivity alone must not disable a still-visible window. Stop repeating animation transactions while ineligible and resume active visuals on reveal. Recheck state at delayed completion. Scope this to artwork first, not a global render freeze. Expected benefit is removal of that measured animation work, with no numerical speedup claimed. Risks: phase discontinuity, lost hover response, Reduce Motion behavior, nested host identity changes.

Priority 1: if mirror snapshots persist without a visible destination, make the mirror task eligible only while its destination can render. Recheck destination visibility after snapshot awaits; prevent stale publication and competing mirrors from increasing sampling unnecessarily. Preserve source ownership, media, capture and form-state rules. Benefit is avoiding approximately one request per second per eligible mounted mirror under the existing loop; actual savings depend on snapshot cost. Risk: stale image immediately on reveal; refresh once on resume.

Priority 2: clear pending hover activation and visible hover card on hide/miniaturize/occlusion of its source window, then allow normal pointer-driven activation on return. Recheck pending task eligibility after sleep. Do not indiscriminately dismiss when merely inactive: visible background windows remain observable. Expected benefit is avoiding stale-card 0.5 Hz polling and unintended snapshots when the specific failure reproduces. Risk: hover continuity and accessibility behavior.

Priority 2: distinguish selected tab from visual visibility in periodic preview snapshots. Suspend visual preview work for unobservable windows, refresh on reveal when stale, and preserve necessary independent media/activity work. Benefit is occasional avoided snapshots; insufficient alone to explain continuous 60 Hz work without evidence.

Priority 3: only after cause/rate attribution, narrow expensive observable reads, cache unchanged mesh colors, or avoid redundant artwork host-root assignments. Preserve the existing sidebar projection cache, IDs, lazy lists and observation architecture. Measure hit rate and invalidation counts before adding another cache or Equatable wrapper.

Do not remove glass, Haze, noise, active animations, functional progress updates, or media polling to obtain an artificial improvement. The diagnostic static-versus-animated probe is a controlled experiment, not a proposed loss of active visuals. No production fix or whole-app before/after speedup is claimed in this revision.

## Instrumentation and controlled runtime protocol

Existing useful probes include `sidebar.projection.resolve`, `workflow.webview-hosts.resolve`, `webview.host.attach`, benchmark window key/occlusion events, and the exported SwiftUI cause graph. These already cover several seams. The benchmark visibility events require `ASTRA_PERFORMANCE_BENCHMARK=1`; it is not a general per-window visibility recorder and also enables other benchmark behavior. Do not turn it on in only one comparison arm.

If clean Time Profiler cannot identify the owner, add opt-in **Debug-only** aggregate counters/signposts at the measured seam: artwork host updates/layout, mirror requests/completions, hovered card sampling, and specific view bodies. Tag each window anonymously and emit lifecycle snapshots at notifications, not every frame. Counters must not use observable state or trigger redraws. Flush bounded aggregates outside the body; no console printing inside each evaluation. Never treat instrumented counts as a clean CPU baseline. Additional Swift instrumentation has not yet been added because existing trace tables should be analyzed first.

For each scenario, allow 15 s to settle, record 30–60 s, repeat three times, and record app revision/configuration, diagnostics/debugger, power/thermal condition, tab/window count and action timestamps. The 50–58 s snapshot task needs at least 120 s. Long idle should include several minutes, keeping independent sync intervals visible as discrete events rather than confusing them with rendering.

| Scenario | Required distinction and acceptance observation |
| --- | --- |
| Foreground idle | Stable inputs; finite transition completes; no unexplained continuous body/layout cycle |
| Background but visible | Continue necessary appearance/rendering; app inactivity is not occlusion |
| Other macOS Space | Capture occlusion and Space transition; no continuous unobservable visual task after settling |
| Minimized | Record miniaturization separately from app state; task stops and resumes correctly |
| Hidden via Command-H | All windows remain open; verify hidden state through notification snapshot; avoid bringing Astra forward during capture |
| Fully occluded | Cover entire destination; distinguish partially visible control case |
| Two windows, one visible | Test distinct tabs and duplicated selected tab; visible window keeps required work, hidden mirror stops |
| Two windows, none visible | No multiplied mirror/animation cost merely because windows remain mounted |
| Low Power Mode on/off | Repeat matched scenarios; no assumption of system throttling replacing app lifecycle cancellation |
| Hover then leave/hide | Debounce/dismissal cancels, card unmounts, no subsequent memory-sampling loop |
| Open/dismiss popover | Pending request cancellation and no repeating redraw after dismissal |
| Loading then idle | Progress stops, completion hides once, no continuing estimated-progress storm |
| Mini hidden/closed | Hidden host versus controller teardown distinguished; media confirmation preserved |
| Appearance/tab/scroll changes | Finite necessary work, stable selection/identity, geometry follows viewport; visuals remain identical |

Compare clean detached Debug and Release first. Separately compare diagnostics enabled and SwiftUI tracing enabled. Use Time Profiler/CPU Profiler independently of SwiftUI to measure baseline. Attribute Astra main/background threads separately from WebKit processes and compositor/GPU activity. Report body evaluations per second, layout counts, sampled inclusive/exclusive weights and CPU with explicit denominators. No universal zero-CPU threshold is appropriate for a browser with legitimate background work.

Offline analysis and regression check:

```sh
python3 checks/render-trace-analysis-check.py
python3 scripts/analyze_render_trace.py \
  /Users/omeriadon/Downloads/exported-tables.zip \
  --json docs/performance/2026-10-14-render-trace-summary.json
```

The analyzer streams XML and resolves table-local references. Its fixture checks nanosecond units, CPU integration, and backtrace/binary reference handling. Raw recordings are kept outside Git. Runtime commands are handed to the user and not executed automatically, as requested.

Clean capture protocol (executed for the archived Release arm above): quit the Xcode-launched Astra process; launch the Release app through Finder/LaunchServices instead of Xcode. Preserve the restored windows and record whether About/Update or duplicate selected-tab windows are open. Wait 15 s, hide via Command-H, then run the following without reactivating Astra or stopping the capture early:

```sh
astra_pid="$(/usr/bin/pgrep -x astra)"
case "$astra_pid" in
  ''|*[!0-9]*)
    /bin/echo "Expected exactly one Astra process: $astra_pid"
    ;;
  *)
    astra_capture="$HOME/Desktop/astra-clean-hidden-$(/bin/date +%Y%m%d-%H%M%S)"
    /bin/mkdir -p "$astra_capture"
    /bin/ps -p "$astra_pid" -o pid=,ppid=,etime=,command= > "$astra_capture/process.txt"
    /usr/bin/pmset -g custom > "$astra_capture/power.txt"
    /usr/bin/xcrun xctrace record --template 'Time Profiler' \
      --attach "$astra_pid" --time-limit 30s \
      --output "$astra_capture/hidden-cpu.trace"
    /bin/echo "Capture: $astra_capture"
    ;;
esac
```

Read trace metadata before comparing: the Release executable should carry no Xcode diagnostic injection, and the recording must cover the full 30 s. Repeat the same configuration foregrounded and idle. Do not enable SwiftUI tracing in the initial CPU baseline. Subsequent targeted SwiftUI recordings can measure event frequency after baseline validity is established.

Minimal reproduction:

```sh
sh checks/GlassIdleProbe/build.sh
```

Launch the resulting Desktop app normally through Finder/LaunchServices. Select Static media, hide with Command-H, and record Time Profiler by its single PID for 20–30 s. Bring only that app forward, select Media waveform, hide again, and repeat. The media cards differ in symbol-effect eligibility while keeping the glass card and controls fixed. Repeat with Visibility gated waveform to verify a future visibility-gate comparison, and with a visible inactive window to ensure animation continues where output remains observable. The gate's Boolean self-check runs during the build script; it is not a substitute for this native interaction test.

## Remaining evidence

The current media waveform trigger, CPU-only Release cost, and standalone reproduction are confirmed. Unknown: exact visibility during the older supplied trace; its debugger attachment and Settings/duplicate-window state; all remaining window/power scenarios; WebKit child-process and compositor/GPU contribution; precise native display/layout scheduling frequency; foreground responsiveness; and a patched-Astra before/after result. Source gaps alone cannot establish the costs of artwork, mirrors, Haze or periodic snapshots.

Validation completed: Xcode MCP optimized Release build, native Xcode archive, standalone Swift 6 optimized probe compilation, all 16 visibility combinations, valid initial-mode checks, and exported-trace parser reference/unit/stack checks. Production source, dependencies, and user power/accessibility settings were not modified. Investigation artifacts remain in the isolated worktree; no commit or push was made.
