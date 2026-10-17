# Astra performance and binary size checkpoint — 2026-10-10

Branch: `release/0.1+3`. Reference source: `e8669b9` with the final launch instrumentation. Candidate implementation: `6b3cb2c`, `27c7281`, `903c939`, and `fd04b28`. Existing local commit `e8669b9` is preserved. Final remote checks are recorded in [PR #13](https://github.com/omeriadon/astra/pull/13).

## Findings

The website runtime is 29.8% smaller in Debug and 30.0% smaller in Release. Whole-app logical size falls 6.1% and 4.0%, respectively. The main executable size is unchanged in each matched configuration. These changes establish a binary-size improvement. They do not establish a startup, CPU, or memory improvement.

## Changes and protected behavior

- Removed the runtime MarkdownView dependency; the browser retains MarkdownView and every required package resource bundle.
- Excluded nine desktop/chat-only sources: chat model, chat history, chat title feature, AI tab divider, media activity view, spaces bar, downloads sidebar, desktop variable blur, and desktop window-focus reader.
- Guarded chat-only stored state, preview chat controls, and chat-turn parsing. Website windows never render the desktop chat sidebar; its ineffective toolbar toggle is now disabled. Main-browser chat behavior and shared Web Search/tool permissions remain present.
- Corrected launch-cache actor diagnostics by making its immutable bounds, value initializer, and pure favicon-bounding function nonisolated. Mutable decoded-cache state remains on MainActor. Removed an unused zoom-default read; BrowserTab retains the existing zoom fallback.
- Added process-birth measurement using public libproc information, OSLog JSON parsing, PID/birth filtering, readiness validation, and regression self-checks. First-main-log timing is explicitly a proxy for main entry, rather than an exact dyld duration.
- Preserved window-restoration order, the 400 ms first-update gate, session data, shared settings, navigation, reader resources, extensions, downloads, protected media/unsaved state, and the updater loading boundary.

## Method and scope

MacBook Air Mac14,2, Apple M2 (8 cores), 16 GB RAM; macOS 27.2 build 26B5101f; Xcode 27.2 beta 2 and Apple Swift 6.4. AC power, low-power mode off. System WebKit dependency version 625.2.5. Local app metadata is 0.0 (build 3); the release archive workflow overrides it to 0.1 (build 3) from the branch name.

One normal window, 33 persisted tabs, existing user session and selected page. No data reset, forced process termination, cache purge, formatter, or dependency installation. Actual loaded/hibernated counts and protected-media state were not inventoried. This is not a controlled empty-tab or 100-tab benchmark. The selected page and WebKit caches can vary across launches.

A concurrent, uncommitted scroll-event monitor in `BrowserSpacePager.swift` is included identically in both local comparison builds. Its SHA-256 is recorded in `comparison-source-metadata.json`. It is preserved and excluded from this work’s commits. Local startup measurements therefore include that additional change; remote CI builds the committed tree.

All four final series use the same readiness definition: an actual visible-window AppKit update has occurred, browser hydration has finished, the window can become key, and a first responder exists. Current keyboard focus is recorded separately. These runs remained background windows (`first_window_key=false`); foreground activation/input latency, GPU presentation, and selected-page load completion are not measured by this event.

Each configuration has eight fresh processes, graceful quits, seven seconds before log capture, and no Instruments or builds running during timing. No sample is discarded. The first run of each newly copied bundle is retained; subsequent runs have warmer filesystem/trust/WebKit caches. Values are wall-clock time from kernel process birth, including loading before main. At n=8, nearest-rank p95 is the maximum.

## Logical file sizes

Sizes count each real file once, excluding duplicate traversal through framework symlinks. They are not compressed download sizes.

| Configuration / component | Before bytes | After bytes | Reduction |
|---|---:|---:|---:|
| Debug website runtime | 16,876,000 | 11,846,448 | 5,029,552 (29.80%) |
| Debug whole app | 82,900,089 | 77,870,537 | 5,029,552 (6.07%) |
| Debug main browser code | 40,669,760 | 40,669,760 | 0 (0.00%) |
| Release website runtime | 7,681,728 | 5,375,824 | 2,305,904 (30.02%) |
| Release whole app | 57,042,103 | 54,736,199 | 2,305,904 (4.04%) |
| Release main browser code | 24,397,104 | 24,397,104 | 0 (0.00%) |

The final chat-feature exclusion saves another 16,544 Debug bytes after the main dependency/source batch; it saves no additional Release bytes because Release already strips that code.

## Process launch measurements

| Configuration | Before ready median / p95 ms | After ready median / p95 ms | Before / after first-main-log median ms |
|---|---:|---:|---:|
| Debug | 811.3 / 2372.9 | 810.0 / 1949.5 | 49.2 / 47.2 |
| Release | 782.4 / 1626.0 | 795.1 / 1599.3 | 46.5 / 44.6 |

The earlier ~579 ms result measured main-to-first-AppKit-update. It cannot be compared directly with process-birth-to-hydrated-window readiness. No pre-main value is reconstructed for that old result.

Two earlier candidate series used a stricter key-window condition and failed on focus loss; their CSVs are retained. One also logged a 2.1-second startup main-thread stall. They are not substituted into the matched series. All reference/candidate configurations were rebuilt after the readiness correction.

## Release memory and idle CPU

Three app-only libproc samples per build, each after at least 30 seconds idle, with approximately two-second CPU intervals. No Instruments attached during these samples. WebContent/GPU/Network helpers are not assigned to Astra without an explicit ownership mapping.

| Metric | Before median | After median |
|---|---:|---:|
| Resident memory | 179.55 MiB | 176.72 MiB |
| Physical footprint | 158.92 MiB | 156.66 MiB |
| CPU, percent of one core | 0.130% | 0.111% |

The small differences are observations from one existing session, not demonstrated memory/CPU savings or per-tab measurements.

## Instruments and responsiveness

Completed PID-targeted Time Profiler captures: Debug baseline idle, Release reference/candidate idle (12 seconds), and Release reference/candidate startup (15 seconds). Raw traces remain locally in `/tmp/astra-performance/`; only sanitized symbol/weight summaries are committed.

For startup profiling, a tested temporary posix_spawn helper starts the process suspended, Instruments attaches by PID, then SIGCONT resumes it. This avoids duplicate-bundle launch resolution. Artificial suspension is excluded from all latency benchmarks and from startup sample analysis. Both startup captures contain real dyld samples. Instruments emitted a sandbox-extension warning, but trace export and named-frame sampling succeeded.

| Main-thread startup sample weight | Reference | Candidate |
|---|---:|---:|
| Total | 520 ms | 518 ms |
| dyld / Mach-O | 41 ms | 34 ms |
| SwiftUI / AttributeGraph | 348 ms | 350 ms |
| AppKit | 482 ms | 476 ms |

These are sampling weights through the readiness event, not measured elapsed durations; inclusive categories overlap. SwiftUI/AttributeGraph remains the larger measured startup opportunity. No rendering-speed improvement is claimed.

An initial all-process App Launch recording failed during serialization and exhausted disk space. Work paused for user cleanup. That failed trace is not used as evidence. Later captures target one PID and are approximately 23 MB each.

The signed production website loader successfully loaded the slimmed runtime. Live checks passed for rendering, same-origin navigation, Back, toolbar hide/show, retained textarea content across toolbar changes and Back navigation, extension menu resources, and the shared extension settings page. These prove the exercised interactions; they are not a complete feature, media, or leak audit.

## Verification

- Xcode MCP Debug and Release builds pass for reference and final candidate, with matched instrumentation. Final builds have no Swift actor-isolation diagnostics; only AppIntents metadata-extraction notices remain.
- All four comparison bundles pass `codesign --verify --deep --strict`, website helper/version/resource checks, single-C-entry export/local-symbol stripping checks, and otool dependency audits.
- Browser code links neither website runtime, updater runtime, nor Sparkle eagerly. Website runtime does not link Sparkle; the lazy updater owns it.
- Local persistence/restoration, ownership, history cancellation, bookmark projection/scaling, automatic hibernation, download IO/file worker, extension lifecycle/file worker, resource policy, noise, favicon observer, release packaging, helper preparation, workflow diagnostics, parser, and process-birth helper checks pass.
- Eight independent remote workflows are checked against the final published head; results are recorded on PR #13.

## Remaining opportunities and limits

A controlled fixed-page matrix at 1/10/50/100 tabs, foreground input acknowledgement, tab-switch frame latency, SwiftUI/Animation Hitches recordings, WebKit helper attribution, sustained media/capture/download scenarios, and leak/allocation investigations remain unverified. Optimize the measured SwiftUI/AttributeGraph startup work only with interaction checks for paging, grouping, drag/drop, and selected-row scrolling.

No notarized distribution, live Sparkle installation, iOS build, or whole-browser performance/regression certification is claimed.
