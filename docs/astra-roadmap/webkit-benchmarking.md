# Astra WebKit benchmark protocol

This protocol records process-level evidence for the WebKit lifecycle work. It
does not claim a per-tab memory value: WebKit exposes content, GPU and network
processes, and those processes can be shared by several tabs. The helper keeps
the process identity (`pid` plus kernel start identity, with `lstart` as a fallback) and deduplicates repeated rows. It
reports RSS as an estimate and derives CPU from cumulative process time across
two samples.

## Commands

From the repository root:

```sh
python3 scripts/webkit_benchmark.py self-test
python3 checks/webkit-benchmark-check.py
python3 scripts/webkit_benchmark.py snapshot --pid ASTRA_PID \
  --webkit-pid WEBCONTENT_PID:webcontent --webkit-pid GPU_PID:gpu \
  --webkit-pid NETWORK_PID:network --output /tmp/astra-before.json
python3 scripts/webkit_benchmark.py snapshot --pid ASTRA_PID \
  --webkit-pid WEBCONTENT_PID:webcontent --interval 30 \
  --output /tmp/astra-idle-cpu.json
python3 scripts/webkit_benchmark.py snapshot --pid ASTRA_PID \
  --webkit-pid WEBCONTENT_PID:webcontent --output /tmp/astra-after.json
```

The helper attributes only PIDs explicitly supplied by the operator. It never
guesses from executable paths, process descendants, or the current Python PID.
WebKit XPC helpers commonly have a launchd parent and cannot be safely assigned
to Astra by ancestry; map each observed helper PID explicitly. Unmapped WebKit
process identities are listed as `unattributed_webkit_processes` without being
included in browser totals. The helper records executable basenames only; it
does not export command arguments, page text, credentials or URLs.

| Value | Source | Meaning |
| --- | --- | --- |
| `rss_bytes` | `ps rss` | Resident size estimate; useful for trend comparisons, not physical footprint |
| `footprint_bytes` | `proc_pid_rusage` `RUSAGE_INFO_V4` | Public macOS physical footprint when the selected PID permits it |
| `rusage_cpu_nanoseconds` | `proc_pid_rusage` | Cumulative user plus system CPU time for interval deltas |
| `cpu_seconds` | `ps time` fallback | Cumulative CPU time when libproc is unavailable |

If a selected PID is absent, it appears under `unavailable_selected_pids` and
its zero total must not be interpreted as zero memory. Permission failures,
process exit and unsupported hosts are reported through this same absence path.

The `time` subcommand is a generic command wall-clock helper and is not an app
startup measurement. Use Astra's structured performance logs for first-window,
first-render and navigation boundaries. Do not pass credentials, page text,
full URLs, query strings or form contents to the helper.

The process totals cover only the explicitly mapped browser PIDs and are
deduplicated within each snapshot. `webcontent`, `gpu`, and `network` totals are
not exclusive to a tab. A process that cannot be classified is retained under
`other`; missing selected processes are reported as unavailable rather than inferred. Process
replacement is visible as a new `pid@start` identity. Compare identities before
and after hibernation to check whether WebKit actually released a process.

## Baseline and final runs

The clean baseline branch `release/0.1+3` at `05af546` compiled successfully
through the Xcode 27.2 beta 2 GUI build workflow. This records compilation only;
no Astra runtime benchmark was executed against the active debug instance, so
there are no baseline memory or CPU numbers yet. Repeat the same build and
runtime protocol after integration before making performance claims.

Record the exact Astra commit, build configuration, macOS build, Mac model and
memory, WebKit framework build, power mode, network condition, number of
windows, loaded/hibernated tab counts, and whether Instruments was attached.
Run baseline on the clean target branch, then repeat after integration with the
same URLs, ordering, wait time and window state. Use five repetitions for
startup and switching timings. Keep cold process-launch and warm cache results
as separate series. Report median and range; keep outliers with their reason.

For idle CPU, use `--interval 30` after a stable idle period. The result derives
CPU seconds from cumulative `ps time` values and reports percent of one CPU core
over the interval. It is process CPU, not energy or scheduler wakeups. For a
stronger interval measure, use Instruments or Activity Monitor and record that
tool explicitly. The helper itself performs only two `ps` table reads and must
not run continuously.

## Manual scenarios

Run each scenario on baseline and final builds. Capture before, after-stable,
and after-close/hibernate snapshots where applicable. Record tab counts,
visible tabs, protected activity, first usable window, page-load completion,
switch-to-visible, switch-to-detached, and switch-to-hibernated durations.

1. One empty tab.
2. One ordinary website.
3. Ten background tabs.
4. Fifty restored tabs.
5. YouTube actively playing.
6. YouTube paused.
7. YouTube backgrounded.
8. Repeated YouTube navigation and closing.
9. Multiple windows and Spaces.
10. Tab switching while another tab plays audio.
11. Memory pressure with an unsaved form and an active download.
12. Rapid creation, closure and restoration of tabs.

For every case verify visible tabs stay awake, active media/PiP and capture stay
active, downloads continue, unsaved forms survive, permissions and private
session boundaries remain unchanged, and back-forward navigation still works.
For hibernation cases, record whether the WebContent process identity vanished,
whether a replacement appeared on wake, and whether scroll, zoom, history and
interaction state were restored.

## Interpretation

Lower mapped browser RSS after hibernation is evidence of reclamation only when
the relevant WebContent identities disappear or shrink after the workload has
settled. A lower tab row value alone is not evidence. GPU/network memory is
shared and should be presented as browser-wide process memory. JavaScript heap,
video buffers and graphics allocations are not separated by this public
measurement; use Web Inspector or Instruments for those questions.

The Search reference uses a bounded sleep timer and memory-pressure events,
then snapshots before releasing a page. Its `bench` tool drives an already open
browser through a local socket. Astra's protocol borrows the repeatable
before/after measurement boundary while keeping the helper independent of
private WebKit APIs.

## Environment limitations

The helper requires macOS `ps` output and a running Astra build for real WebKit
measurements. CI or a Linux host can run its parser and identity self-checks,
but cannot certify WebKit process replacement, memory pressure, rendering,
media, Spaces, or Swift actor/thread-affinity behaviour. No result should be
invented when those runtime cases cannot be exercised.

## Integrated implementation and verification

The initial release base was `05af54619cbcc4724800889f01e90d948eb37235`.
Six isolated implementation branches were merged, followed by semantic fixes
for shared scheduling, activity validation, process identity, and restoration.
The implementation preserves the existing four-controller warm host budget.
Ordinary inactive macOS pages detach while their controller retains the same
WebView; protected pages retain attachment. Detached quiescent pages skip the
periodic JavaScript activity query. Paused media uses the slower visible-page
fallback; playback and PiP events still refresh immediately.

Automatic hibernation defaults to enabled, with 30-minute normal and five-minute
warning thresholds. Critical pressure reclaims eligible tabs sequentially,
oldest first. Every async boundary rechecks selection across windows, controller
and navigation identity, activity time, pressure state, and the setting.
A one-shot form-state query runs before reclamation in the isolated script world;
changed fields and query failures prevent teardown. This query is not added to
the periodic media observer. Pinned/favourite tabs, pending dialogs, captures, media, downloads, live popups,
weakly tracked popup opener dependencies, unknown activity results, and oversized or unknown interaction-state blobs are
preserved. A single captured interaction-state blob is reused for teardown;
normal tabs retain its encrypted copy rather than a second raw copy. Historical
URL prefixes outside WebKit's live back-forward list survive encrypted restore.

Memory diagnostics report observed process footprints, separate shared GPU,
network and model processes, deduplicate process identities, and do not claim
JavaScript heap or exclusive tab memory. Reclamation logs resample the original
process identities after teardown; unavailable information is not reported as
zero bytes reclaimed. This is a bounded diagnostic task, not a continuous
browser-wide sampler.

The read-only `_displayCaptureState` probe is a new safety dependency because
this SDK has no public screen-capture lifecycle query. It is selector guarded;
unknown state prevents automatic hibernation. It does not change WebKit feature
flags. Disabling automatic hibernation reverses the policy. Distribution must
continue to tolerate guarded WebKit SPI already used for process identifiers
and existing browser features. Process footprint inspection itself uses public
`proc_pid_rusage`.

Executed checks include the production hibernation manager with isolated
collaborators under Swift 6 complete concurrency checking, native AppKit/WebKit
host transitions, process identity aggregation, ownership/transfer/private
isolation, permission policy, media/PiP scripts, native rule validation including
concurrent validation, interaction-state history prefixes, navigation reload,
and diagnostic export limits. The macOS target builds using the Xcode app's
scheme build API; no `xcodebuild` command was invoked.

The iOS simulator build is blocked by the project's Sparkle module dependency:
Clang dependency scanning cannot resolve Sparkle for the simulator. This change
does not modify the existing Sparkle linkage or update manager. Full iOS app
compilation remains unverified. macOS-specific process inspection and host
attachment code remain conditionally compiled.

A broader regression sweep reproduced existing failures on the clean baseline
in AI archive/usage/features, sync, sidebar/window fixture extraction, Today
cleanup/sections, old media eligibility expectations, and hover-script fixtures.
The reload and window-ownership fixtures needed for this work were repaired.
The broad suite is not reported as passing.

CPU counters are Mach absolute-time ticks, converted with the public
`mach_timebase_info` ratio before interval calculations. An executable check
compares the converted delta with process CPU time on this Mac, including
Apple Silicon timebase scaling. The binding follows
[Apple XNU resource accounting](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c).

The utility libproc binding was exercised with 100 calls on the benchmark
process: median 0.0097 ms and maximum 0.0186 ms on this Mac. This measures the
sampler binding only; it excludes WebKit selectors, UI overhead, and website
workloads. It is not an Astra memory or CPU improvement measurement.

No baseline-versus-final Astra workload measurements are claimed. Computer-use
access returned `cgWindowNotFound`, and the active user browser was not used as
an isolated benchmark fixture. Real YouTube, Spaces, restoration rendering,
media continuity, physical memory recovery and switching latency still require
the manual scenarios above. The native host runtime check verifies actual
AppKit attachment with WKWebView, but uses a controller collaborator and does
not certify an end-to-end website workflow.

Rejected changes: reducing the warm budget without latency evidence; full
`.suspend` while critical page/extension tasks cannot all be observed; process
pool sharing (deprecated and without an effect on current WebKit); forced video
quality changes; Search's private frame-rate/autoplay flags; and blank-page
navigation as a substitute for destroying a WebView.

Sources: [Apple scheduling policy](https://developer.apple.com/documentation/webkit/wkpreferences/inactiveschedulingpolicy-swift.property),
[Apple media playback state](https://developer.apple.com/documentation/webkit/wkwebview/requestmediaplaybackstate(completionhandler:)),
[Apple process-pool deprecation](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/processpool),
[Search Sleep.swift](https://github.com/driceroland/Search/blob/main/Sources/Search/Sleep.swift),
[Search Tab.swift](https://github.com/driceroland/Search/blob/main/Sources/Search/Tab.swift),
[Search Shield.swift](https://github.com/driceroland/Search/blob/main/Sources/Search/Shield.swift),
[Search FrameRate.swift](https://github.com/driceroland/Search/blob/main/Sources/Search/FrameRate.swift),
[Search Browser.swift](https://github.com/driceroland/Search/blob/main/Sources/Search/Browser.swift),
[Search benchmark](https://github.com/driceroland/Search/blob/main/Sources/Search/Bench.swift),
[Search changelog](https://github.com/driceroland/Search/blob/main/CHANGELOG.md).
