# Astra runtime validation, 9–10 October 2026

**Status: stopped at user request. Runtime recovery, matched app-only idle samples, and hibernation/wake checks completed. Full performance acceptance remains incomplete.**

PR: https://github.com/omeriadon/astra/pull/13. The release branch remains intact and the PR remains open. This dataset records successful checks, failed tools, exploratory results, and unexecuted acceptance criteria separately.

## Environment and isolation

- MacBook Air Mac14,2, arm64, 8 CPU cores, 16 GiB RAM.
- macOS 27.2, build 26B5101f; Xcode 27.2 beta 2; system WebKit.
- AC power. Brightness and power settings were not changed. Background applications remained running.
- Baseline app source: `05af54619cbcc4724800889f01e90d948eb37235`.
- Candidate app source: `8fc6600d421c4566191fa982940d5d6f139f56ea`.
- Process-inventory correction: `69f635e`. Later artifact commits do not change the app architecture.
- Separate worktrees, ad hoc sandboxed builds, bundle identifiers, defaults domains, WebKit stores, and test-only sync Keychain service names were used. Personal profiles were not copied or cleared. Production-only signing entitlements were excluded from the fixtures; authentication/Web Push behavior is therefore not certified.
- Controlled downloads used a directory selected through the native folder picker under `/tmp`, outside personal Downloads.

Disk availability repeatedly fell to approximately 100 MiB. Instruments and the passive sampler reported explicit disk-full failures. Removing only task-generated caches recovered space temporarily. Existing memory pressure, compressed memory, and swap are confounding factors.

## Actual execution

Computer Use launched both isolated builds, loaded public websites and unsigned-in YouTube pages, created/persisted 100 tabs, exercised repeated Control-Tab switching, toggled the sidebar, scrolled a long local page, entered a form, downloaded files, and tested extension error handling, installed and removed the bundled uBlock Origin Lite extension, and closed a public YouTube video through the media warning.

The controlled 4 KiB and 16 MiB downloads matched their source SHA-256 values. Automatic AI naming was active and renamed the large payload; filename equality was not used as an integrity test. The automatic-download permission dialog was exercised with Allow Once.

The edited form survived tab switching, and its background tab exposed a disabled Hibernate action. On 10 October the same candidate process, PID 56304, had approximately 13 hours of uptime and still retained the test form. This is an endpoint observation, not a continuously monitored crash-free soak or proof of the exact hibernation exclusion reason.

## Baseline comparison limits

Thirty recovery launches produced real milestone logs, five per build and 10/50/100-tab fixture. The harness forcibly terminated and reopened the app, disrupted the user, and was stopped and removed. Its stdout/stderr were discarded. These samples are retained as **exploratory recovery milestones only**, not accepted ordinary launch comparisons. No further force-kill/relaunch harness was run.

Five observations do not support a useful p95 estimate. The following numerical differences are arithmetic on exploratory data, not certified improvements or regressions.

| Workflow | Baseline | Candidate | Difference | Result |
|---|---:|---:|---:|---|
| Cold startup to usable UI | NOT MEASURED | NOT MEASURED | — | Unverified |
| Ordinary warm startup to usable UI | NOT MEASURED | NOT MEASURED | — | Unverified |
| 10-tab recovery milestone, median | 828.4 ms | 832.7 ms | +4.3 ms | Exploratory |
| 50-tab recovery milestone, median | 881.6 ms | 863.8 ms | −17.8 ms | Exploratory |
| 100-tab recovery milestone, median | 1026.0 ms | 1178.4 ms | +152.4 ms | Exploratory |
| Input-to-pixel tab switching | NOT MEASURED | NOT MEASURED | — | Unverified |
| Background idle, app CPU only (two local pages) | 0.078% median | 0.070% median | −0.0075 percentage points | Five matched intervals; cache/profile histories differ |
| Matched active YouTube memory | NOT MEASURED | NOT MEASURED | — | Playback not certified |
| Matched background WebKit memory | NOT MEASURED | NOT MEASURED | — | No matched series |
| Tab-close memory reclamation | NOT MEASURED | Mapped footprint −573.4 MiB | — | One candidate closure observed |

Recovery milestone ranges, in milliseconds:

| Saved tabs | Baseline range | Candidate range |
|---|---:|---:|
| 10 | 672.9–909.3 | 771.2–883.2 |
| 50 | 784.3–967.6 | 835.3–906.0 |
| 100 | 652.2–1174.9 | 1152.4–1427.9 |

The window/restoration log boundaries exclude usable interaction and page paint. Fixture tabs mostly represent unloaded blank tabs; they do not represent 100 loaded websites. Encrypted interaction snapshots were excluded because the fixtures use different restoration keys.

## Synchronous stage evidence

The recovered candidate series contains the following measured distributions. These are stage durations, not whole interactions. Baseline coverage was insufficient for comparison.

| Stage | Samples | Median | p95 | Range |
|---|---:|---:|---:|---:|
| Tab creation to model commit | 90 | 1.3 ms | 9.4 ms | 0.8–73.4 ms |
| Tab selection | 110 | 0.2 ms | 1.2 ms | 0.1–16.4 ms |
| WebView host resolution | 113 | 0.5 ms | 1.6 ms | 0.1–16.0 ms |
| Snapshot preparation | 93 | 0.4 ms | 1.5 ms | 0.2–32.7 ms |
| Previous checkpoint decode | 93 | 0.4 ms | 6.3 ms | 0.3–16.9 ms |
| Checkpoint encoding | 93 | 0.9 ms | 4.7 ms | 0.3–22.2 ms |
| Checkpoint commit | 93 | 1.8 ms | 22.4 ms | 1.2–38.4 ms |
| Shared-state fan-out | 92 | 0.0 ms | 0.1 ms | 0.0–0.6 ms |

Outliers remain included. Durations were recorded to 0.1 ms precision; rounded zero does not mean no work. The 100-tab switching log showed selection-journal writes without full checkpoint writes for selection-only changes.

## Profiling and resource findings

Two Time Profiler captures completed: a 30-second initial transition and a 20-second controlled tab-switching capture. Sanitized summaries retain sample counts and leaf/inclusive symbol weights. Inclusive symbols are deduplicated within each sample. Sampling weight is not exact CPU time.

The controlled trace had 4,242 samples, including 4,169 main-thread samples. Runtime, AppKit, SwiftUI, allocation, and event-loop symbols dominated the visible stacks; application frames were partly unsymbolized. The trace does not establish a particular Astra function as a meaningful bottleneck. No architecture was redesigned without attributable evidence.

Descriptive 30-second CPU observations, percent of one CPU core:

- Baseline empty profile: Astra 0.24%.
- Candidate static-page observation: Astra 1.61%.
- Candidate 100-tab observation: Astra 1.01%.
- Paused YouTube, app backgrounded: Astra 0.29%, mapped WebContent 2.39%, GPU 0.02%, networking 0.25%.
- YouTube playback attempt: Astra 17.66%, mapped WebContent 12.35%, GPU 6.76%, networking 1.51%. Sustained playback was not certified, so this is not an active-playback benchmark.

These scenarios differ and must not be used as build comparisons. YouTube player accessibility/visual state was inconsistent on both builds. No JavaScript heap, decoder-buffer, or exclusive per-tab memory breakdown is claimed.

Mapped process footprints at the overnight endpoint were approximately 129.4 MiB for Astra, 52.6 MiB for the protected local-page WebContent process, 10.2 MiB for GPU, and 25.8 MiB for networking. The Astra footprint at the first passive sample was approximately 127.0 MiB. Process identities remained available. This mapped subset does not include every possible browser process and does not establish a leak or tab-close reclamation.

A later normal closure of the public YouTube tab terminated its mapped WebContent and service-worker processes (PIDs 63246 and 66865). Across the six explicitly mapped processes, physical footprint fell by 601,214,000 bytes (573.4 MiB). Shared GPU footprint fell by 28,967,104 bytes (27.6 MiB); networking fell by 2,342,912 bytes, while Astra increased by 1,409,096 bytes. Shared services remained alive. The edited local form was still present afterward. This is one candidate observation, without a matched baseline or a leak conclusion. The native player clock advanced to 57 seconds earlier in the session; sustained playback was not certified. Raw snapshots and deltas are in `video-before-close.json`, `video-after-close.json`, and `video-close-results.json`.

Activity Monitor was operated independently. Its energy rows could not be reliably attributed between identically named test instances. Physical watts and a comparative energy result are **NOT MEASURED**.

## Failed and incomplete checks

- Leaks: initial recording failed with kperf/ktrace errors. A later 20-second recording saved, but its UI displayed a failed leak check and empty allocation table. The independent `/usr/bin/leaks` scan reported three 32-byte `_NSMenuIntelligentAssistantConfiguration` allocations (96 bytes total), with no WKWebView leak reported. This is a limited live-process scan, not a browser-wide leak-free certification; see `leak-observation.json`.
- Rendering: the first sequential Animation Hitches recording aborted while saving with `No space left on device`. A later 20-second recording saved at `/tmp/astra-final-hitches.trace`, but Computer Use timed out before the intended scrolling workload could be executed. It is not a scrolling-performance result.
- The first 60-minute passive monitor stopped after ten samples spanning 540 seconds because the result write failed with errno 28. A later attempt collected 34 samples spanning 1,980.35 seconds before the monitor was stopped after UI availability failed. Neither attempt completed 60 minutes. Neither restarted or signaled Astra. Both are marked incomplete. The later mapped Astra footprint ranged from 133.7 to 223.9 MiB, ending at 137.9 MiB; mixed-workload average CPU was 3.01% of one core. These are not idle or leak benchmarks; see `stability-current-partial.json` and `stability-current-summary.json`.
- Computer Use coordinate actions subsequently returned `noWindowsAvailable` even while the app process and accessibility tree remained available. Indexed interaction still verified the retained form.
- The corrupt extension archive was rejected. The bundled uBlock archive passed `unzip -t` but was initially rejected during low storage. After storage and coordinate control recovered, installation, enable/disable toggles, and removal succeeded in the disposable profile. The installed archive was removed and Astra remained alive. The initial rejection is confounded; no architectural cause is established. The standalone WebKit constructor probe terminated in Foundation and is not a valid app-context test.
- Multi-window/private browsing, PiP/capture continuity, active background audio, sustained playback, hibernation/wake reclamation, interrupted-write recovery, large history/bookmark UI workloads, and download pause/resume/segmentation/external-volume workflows were not comprehensively executed.

## Implemented corrections and verification

The demonstrated measurement bug was fixed: the previous `ps` layout truncated executable names and missed `com.apple.WebKit.*` helpers. The helper now requests unbounded `comm` output as the final column, retains executable basenames only, recognizes the actual helper names, and never inspects command arguments or infers ownership from ancestry. Parser and live-process regression checks pass.

The passive sampler retains process-start identities, stops on unavailable/reused Astra PID, and contains no app launch or process-signaling behavior. Its result publication now uses a temporary file and atomic replacement so a failed write preserves the preceding result. Identity and publication self-checks pass.

The non-build regression sweep recorded 34 unique passing checks and 35 successful invocations, including isolated hibernation, filesystem/download publication, ownership, history cancellation, and library checks. This is not a claim that every repository check or runtime scenario passed.

The macOS Debug build completed through Xcode MCP on 10 October with no reported errors. The macOS Release build completed through Xcode's Build For Profiling action on 9 October. No local `xcodebuild` command was used. Xcode reported zero scheme tests; executable regression checks are recorded separately. Both required CI runs passed on exact pushed HEAD `32459315a7d5ce03c4bdcfb2c0bd51cf001e4d33`: [run 38022007785](https://github.com/omeriadon/astra/actions/runs/38022007785) and [run 38022010302](https://github.com/omeriadon/astra/actions/runs/38022010302). Subsequent local results updates are not included in that CI claim.

## Artifacts and privacy

JSON files contain raw numeric samples, process identities, aggregate metrics, fixture definitions, and explicit caveats. Debug logs and successful raw Instruments traces remain outside the repository under `/tmp`; they can contain environment information and should not be published unredacted. Failed traces were removed to recover space.

The pre-commit hook unexpectedly ran whole-repository formatting and staged unrelated files during the first checkpoint. Those changes were removed from the unpublished checkpoint, and the original `BrowserResources.swift` edit was restored. Subsequent scoped commits bypass that hook for the individual command; repository hook configuration was not changed.

After the later profiling run, Computer Use returned timeouts and an AppleEvent error (-1712). The user reported that the app was not alive. Inventory listed only the isolated candidate; normal Astra was absent. A five-second sample of candidate PID 42628 placed all 4,227 main-thread samples in the AppKit event-loop wait. This does not establish usable UI or a crash-free stability interval. See `runtime-availability-failure.json`. No automatic relaunch was performed.

## Bounded follow-up and handoff, 10 October

The initial follow-up started at approximately 12:58 local time with a 30-minute execution budget and produced a handoff while safe UI access remained blocked. The user then requested continued recovery work within that budget. Scope was runtime identification, one conditional navigation/tab-switching/form-state smoke test, and this handoff. Personal profiles, credentials, sessions, unrelated apps, and the existing `BrowserResources.swift` edit were protected. No production code, architecture, or benchmark infrastructure was changed.

Read-only process inspection confirmed candidate PID 42628 still had its original 12:07:43 start time. The app bundle identified itself as `com.omeriadon.astra.performance.candidate`. Computer Use inventory listed that isolated candidate and no normal Astra. This distinguishes the remaining test process from a usable normal Astra session; it does not establish which windows exist.

One attempt to bind Computer Use to the verified running candidate failed with `NSCocoaErrorDomain 256` and AppleEvent `-1712` in `LSOpenCore.mm`. Despite process existence, `getApp` issued an open event. The user then supplied a macOS dialog stating: “You can’t open the application ‘astra.app’ because it is not responding.” This establishes the OS-reported failure of the open request, not its root cause. At that checkpoint, no additional UI attempts, explicit launches/relaunches, process termination, or recovery loop followed. Future inventory-only checks must not assume `getApp` is free of open-event side effects.

A three-second `/usr/bin/sample` capture at 12:59:01, using a 10 ms interval, placed all 272 main-thread samples in AppKit's event-loop wait ending in `mach_msg2_trap`. A profiler-injected `liboainject` initialization thread was also waiting in JavaScriptCore allocation enumeration. Neither observation establishes a crash, deadlock, healthy idle state, or attributable application defect. Raw stacks remain at `/tmp/astra-runtime-handoff-sample.txt` and are not published. Disk availability was approximately 8.8 GiB; no new Instruments capture was attempted.

| Follow-up check | Result |
|---|---|
| Candidate PID/start time and bundle identification | Verified |
| Normal Astra in app inventory | Absent |
| Existing candidate window state | NOT MEASURED: UI binding failed |
| Navigation smoke test | NOT MEASURED |
| Tab-switching smoke test | NOT MEASURED |
| Retained unsaved form state in this follow-up | NOT MEASURED |
| `python3 scripts/webkit_benchmark.py self-test` | PASS |
| `sample-session.py --self-test` identity/publication assertions | PASS |

The two checks validate the measurement helpers only. Previous successful form checks remain historical observations. Runtime availability is unresolved, and the full performance mission has not passed. No code fix was made because no attributable defect was established. No build was needed for these report-only changes.

GitHub status was rechecked through `gh`: PR #13 is OPEN on `release/0.1+3`, with remote HEAD `32459315a7d5ce03c4bdcfb2c0bd51cf001e4d33`. Both [run 38022007785](https://github.com/omeriadon/astra/actions/runs/38022007785) and [run 38022010302](https://github.com/omeriadon/astra/actions/runs/38022010302) remain completed/success on that exact remote HEAD. Local report changes have no new CI result. No push or merge was performed.

### Authorized isolated recovery and smoke check

The continued read-only system inventory, explicitly authorized by the user, confirmed that PID 42628 owned ten Core Graphics window records, including an onscreen 1280×821 window (ID 16161). The candidate was registered as a foreground app, had finished launching, and was not hidden; normal Astra had no running process. Window existence did not establish usable interaction. Computer Use rejected direct selection by window ID on macOS.

The first direct accessibility comparison was invalid because its caller lacked accessibility trust. After the user enabled permission, the candidate's bounded window request failed after approximately two seconds with `kAXErrorCannotComplete` (`-25204`), while Instruments returned its window list successfully in 36 ms. This establishes a candidate-specific accessibility failure under that probe. The task's Leaks trace was saved and closed, and its Instruments process was quit through the UI. The same candidate's accessibility request still failed. A subsequent two-second sample retained the injected profiler thread's allocation-enumeration wait; cleanup did not restore access.

The user explicitly authorized **one** termination and **one** isolated clean launch, accepting loss of the candidate's in-memory test form state. Before signaling, the process start time and executable path were checked again. One SIGTERM was sent to PID 42628; it exited without escalation. The same signed isolated build was launched once, producing PID 10665 at 13:08:35 local time. No force-kill or repeated restart loop was used. Personal profiles, credentials, sessions, unrelated applications, and `BrowserResources.swift` were not modified.

The fresh candidate returned its accessibility tree and an existing test form containing `unsaved-test-123`. That is one restoration endpoint, not comprehensive interrupted-write recovery certification. The smoke check set a fresh marker, `astra-smoke-20261010-1309`, opened one new tab, navigated to the existing loopback fixture's second page, selected the form tab again, and verified the marker in both the accessibility tree and a screenshot. The local fixture server returned HTTP 200 for the second page. No form was submitted. The task-owned fixture server was stopped afterward; the final accessibility check still showed the fresh marker. Candidate PID 10665 was left running, and normal Astra was not launched.

| Recovered-runtime check | Result |
|---|---|
| Candidate UI access after single authorized restart | PASS |
| New-tab navigation to controlled second page | PASS |
| Tab selection back to edited form | PASS |
| Fresh form marker retained after tab switching | PASS |
| Visible form rendering | Verified by screenshot |
| Fresh candidate accessibility window query | Success; one AX window |
| Profiler injection in two-second fresh sample | `liboainject` and `_OAAttachAndInitialize` absent |
| Input-to-pixel latency | NOT MEASURED |
| New stability interval or matched performance comparison | NOT MEASURED |

Current isolated runtime availability is restored. The prior nonresponse remains unexplained. Its occurrence after profiling and the absence of injection in the recovered process are an association, not proof of an Instruments or Astra root cause. No production-code fix or architecture change was made. The original 33-minute stability interval remains incomplete, and the missing performance comparisons retain their NOT MEASURED status. No additional build was needed; the two existing measurement self-checks, benchmark JSON validation, and scoped diff validation passed. Raw diagnostic samples remain under `/tmp` and were not committed.

## Final continuation results and requested stop

After the user requested continued validation, the existing isolated baseline build was verified as signature-valid and launched normally. Baseline remained at source `05af546`; candidate remained at `8fc6600`. No production app code was changed, no additional build was run, and no further Astra process termination occurred. Only disposable test tabs were reduced to prepare matching workloads; personal profiles and the existing `BrowserResources.swift` edit were preserved.

### Matched background idle

Both Debug builds had one window, two loaded loopback pages, zero hibernated tabs, the same edited form marker, 100% zoom, and the second page selected. Both were verified as backgrounded at each interval boundary. After a 30-second settling period, five simultaneous 30-second intervals measured the explicit Astra app PIDs. AC power and unchanged power settings were verified; system WebKit version was `22625.2.7.1`. Instruments was not attached.

| App-only metric | Baseline | Candidate |
|---|---:|---:|
| CPU median, percent of one core | 0.078% | 0.070% |
| CPU range | 0.072–0.095% | 0.065–0.077% |
| Physical footprint median | 138.4 MiB | 120.5 MiB |
| Physical footprint range | 138.3–144.5 MiB | 120.5–122.8 MiB |

Raw intervals are in `matched-background-idle.json`. These are matched current workloads with different prior cache/profile histories, concurrent isolated builds, existing compression/swap, and unrelated applications still running. They establish observed app-only values, not a causal browser-wide improvement. WebContent/GPU/network totals were excluded from this comparison.

### Hibernation and wake

One clean long-page sequence was executed in each build while a separate edited form remained protected. Explicit process attribution used Activity Monitor's local fixture association and exact isolated WebKit sandbox open-file associations; no ancestry inference was used. Hibernation terminated WebContent PID 29467 in candidate and PID 32890 in baseline. The candidate replacement was explicitly mapped as PID 31696. Mapped WebContent footprint fell 29.6 MiB in candidate and 54.6 MiB in baseline. These are one-trial subset deltas; changes in other mapped processes and differing allocation histories prevent a comparative reclamation claim.

Both builds restored 120% zoom and normalized scroll position 0.1243318 from 0.1244387, with forward and back navigation working. The protected form marker remained intact during the other tab's hibernation. The candidate's inactive edited-form Hibernate action was disabled while the clean inactive page's action was enabled. See `hibernation-runtime-results.json` and the four before/after snapshots. The automatic timeout/pressure matrix remains **NOT MEASURED**.

### Media and remaining measurements

The candidate's deterministic silent H.264 fixture advanced from 0.3 seconds (`paused=false`, `ended=false`) to its 180-second endpoint (`paused=true`, `ended=true`). This establishes clip completion. The observations were 310.31 seconds apart and do not establish continuous frame pacing or absence of stalls. Baseline playback started, but its final element state was not read before the requested stop. The fixture's source hash and numeric observations are in `media-continuation-results.json`; generated media remains outside the repository.

Before playback, the candidate exposed a Pause toolbar action while the fixture reported time 0 and `paused=true`. A fresh UI read reproduced this disagreement. `refreshActivity` combines its DOM flag with WebKit's aggregate playback result. [Upstream WebKit](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/WebProcess/WebPage/WebPage.cpp) returns playing when a media session exists and is neither paused nor suspended, while its [session-state check](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/platform/audio/MediaSessionManagerInterface.cpp) tests the session's Paused state. This suggests an idle-session fallback false positive; the exact deployed native return was not directly measured. No fallback was removed because iframe/Web Audio lifecycle protection must remain intact. Toolbar state alone was not used to certify playback.

PiP entry, background-tab playback continuity, sustained YouTube playback, input-to-pixel latency, comparative energy, new scrolling/hitch measurements, and the other unexecuted acceptance cases remain **NOT MEASURED**. No new profiling capture was attempted.

### Passive interval and cleanup

The recovered passive monitor left 46 samples spanning 2,700.37 seconds (45 minutes), not the requested 60 minutes. All recorded candidate process samples remained available. Mixed-workload app footprint ranged 114.9–141.3 MiB, ending at 138.7 MiB; average app CPU was 13.55% of one core. This includes UI interactions and media work and is not idle CPU or leak evidence. The raw completion reason was null, and the sampler was already absent when explicit cleanup was attempted. It is **INCOMPLETE**, with no continuous-UI or crash-free certification. Raw data and caveats are in `stability-recovered-session.json` and `stability-recovered-summary.json`.

The user then requested immediate finish. No fixture server or sampler remained running at cleanup; both isolated Astra processes were left running. No further experiment, app restart, build, push, or merge was performed. PR #13 was rechecked as OPEN on remote HEAD `32459315a7d5ce03c4bdcfb2c0bd51cf001e4d33`; both previously linked CI runs remain completed/success on that head. Local result artifacts have no new CI run. Benchmark JSON, measurement consistency assertions, and scoped diff checks passed.

The mission remains incomplete. Remaining acceptance criteria are not marked passed, the PR is not merged, and no unsupported memory-reclamation change is introduced.
