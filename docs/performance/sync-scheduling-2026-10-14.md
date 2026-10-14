# Sync scheduling and CPU overhead

Base: build 3, `4825a35d8f872901a97ede3ff64ae7cb532568be`.

## Architecture

Local mutations invalidate a revision and mark remote data pending. They still
schedule independent local checkpoints and journals. Completing a disk write no
longer launches networking. Checkpoints retain serial off-main encoding and file
work, atomic replacement, backup/privacy checks and recovery. A process-wide
capture sequence rejects older full snapshots even across separate window queues.

The main-actor coordinator owns UI status and browser application. One scheduled
task and one active task enforce periodic pulls, including unchanged devices:
180 seconds normally, 600 seconds in Low Power Mode. Startup and manual requests
run immediately; reconnect/wake catch up when eligible. Power transitions recompute
the deadline. Edits cannot push the deadline back. Offline/sign-out/readiness gates
remove the timer. Failure retries use bounded exponential backoff with jitter
(maximum 1800 seconds). Authentication failures require sign-in again.

The engine actor owns sync transport, response decoding, URL validation, portable
projection, cross-window merge, local-only preservation, comparison and upload
encoding. Snapshot/projection caches use browser, settings and global content
generations, including Boost changes. Closed windows are evicted. Remote payloads
are decoded and validated once per cycle. Uploads are skipped when the outgoing
document matches the device's decoded server snapshot.

Every asynchronous merge rechecks settings, window membership and revisions before
applying anything. There is no suspension between the final check and browser
application. Changes during upload remain pending. Continuous edits bound the
number of rebases per attempt rather than creating an unbounded CPU loop. Wire
versions, tab UUIDs, conflict semantics, tombstones, private/local exclusions and
payload limits remain compatible.

The source Handoff activity has a delegate that requests immediate publication
when the activity is actually continued on another device. This preserves new-tab
UUID availability with delayed periodic uploads; merely advertising/selecting a
tab does not initiate a sync. Busy Handoff requests queue an awaited follow-up.

Account settings exposes production Sync Now, progress, static pending status,
last successful completion and errors. Concurrent manual API callers wait for the
active task and a coalesced follow-up. Internal scheduler/revision fields are
excluded from Observation.

## Confirmed hotspots

Both sync URL validators previously built the union of whitespace and control
CharacterSets inside the scalar predicate. They now reuse an immutable static
set. The same pattern was removed from local reading-list and Easel URL checks.
Projection classifies tabs and bookmarks once; validation avoids concatenating
temporary URL arrays. The coordinator no longer reconstructs three full documents
per successful sync or decodes the device snapshot twice.

The old logging backend gated info and notice before calling `Logger`, unless
`ASTRA_LOG_VERBOSE` or `ASTRA_PERFORMANCE_BENCHMARK` was enabled. `log stream
--level debug` cannot recover an event never emitted. Essential sync events now
bypass that gate and emit notice events; expensive engine phases have signposts.
Essential metadata contains fixed reasons, counts, sizes, power state and timings.

```sh
log stream --style compact --level info \
  --predicate 'subsystem == "com.omeriadon.astra" AND category == "sync"'
```

Subsystem/category and emission are checked against source and the logging test.
Actual Terminal output must be verified on macOS; this Linux workspace cannot run
Apple unified logging. CI now also runs this exact predicate around the logging
fixture and requires its essential `sync.check` event to appear.

## Reproducible validation and measurements

Use Xcode 27 / Swift 6.4 (`bash scripts/ci/select-xcode-27.sh`). The existing Swift
Model Tests workflow now runs the production scheduler, actual coordinator task
methods with controlled boundary work, actual URL validators and baseline
benchmarks, real document integration fixtures, persistence revision/recovery
fixtures, engine tests, large-account benchmark and logging checks. The persistence
workflow also verifies mutation/write/network separation. Debug build and Release
archive workflows compile the app.

```sh
swiftc -swift-version 6 astra/Storage/BrowserSyncSchedule.swift \
  checks/sync-scheduler-check.swift -o /tmp/astra-sync-scheduler
/tmp/astra-sync-scheduler
python3 checks/sync-coordinator-check.py
python3 checks/sync-url-validation-check.py
bash checks/run-sync-models.sh
```

The validator benchmark runs the production validator and an otherwise identical
version with the previous per-scalar union, in both Debug and Release. The model
benchmark uses 400 tabs, 1800 bookmarks and 15000 history visits and prints phase
timings. Keep CI stdout as the measurement record; hardware and compiler matter.

Observed on the macOS ARM64 Xcode 27.2 / Swift 6.4 runner in
[run 38500954252](https://github.com/omeriadon/astra/actions/runs/38500954252):

| 100,000 URL validations | Previous union expression | Cached set |
| --- | ---: | ---: |
| Release | 12,145.03 ms | 155.43 ms |
| Debug | 11,476.28 ms | 289.50 ms |

These are single matched microbenchmark runs, with otherwise identical validators,
and do not establish whole-app CPU or energy changes. That run was superseded by
a later commit after all scheduler/coordinator/model/persistence/engine fixtures
passed; its final logging-test compilation exposed a missing Keychain error-model
dependency, which was then added.

The same runner's large-account Release benchmark measured projection 73.66 ms,
validation 26.81 ms, encoding 73.22 ms and decoding 124.39 ms, with a 3,226,468-byte
document. These are post-change-only measurements, without a matched full-document
baseline. Explicitly calling projection again took 57.24 ms; scheduled engine
cache reuse avoids that call when its source generations are unchanged.

For matched native app profiling, build this branch and the base with the same
configuration, account fixture and server. Use a separate fresh output directory
for each run:

```sh
bash scripts/profile_sync.sh APP_PID 660 /tmp/astra-sync-after-background-lpm
```

Run foreground/background, Debug/Release, Low Power Mode on/off, startup,
scheduled and manual cases. Keep websites idle and the account/server unchanged.
Capture startup with a launch Time Profiler recording separately because an attach
cannot measure work before attachment. The script records process CPU/RSS,
power configuration, lifecycle logs and Time Profiler. Inspect signposts for
snapshot, decode/validation, projection/merge and encoding; use Energy Log for
wakeups/energy. Set `ASTRA_LOG_VERBOSE=1` equally for both builds when counting
local checkpoint events. Counts from essential sync events reveal cycle and upload
frequency. Do not infer idle CPU from the synthetic validator benchmark.

## Remaining measurement limits

This local workspace has no Swift compiler, macOS, Instruments or running Astra account.
No foreground/background CPU, energy, peak-memory or cross-device runtime speedup
is claimed here. CI execution and native profiling are separate evidence.
Capturing live browser values and applying UI changes necessarily remain on main;
the disposable launch cache still performs bounded (2 MiB maximum) PropertyList
encoding on main. Synced settings PropertyList processing remains main-actor work.
Full merge equality and server snapshot transfer still scale with account size;
the backend has no incremental sync/ETag contract. The 5,000,000-byte per-device
server limit remains unchanged. Full native two-device Handoff and real sleep/wake,
network failure, power transition and continuous-edit workloads require runtime
verification.
