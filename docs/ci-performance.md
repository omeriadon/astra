# Performance CI

The Build 3 branch adds three informational performance workflows. Normal Debug
build, Release archive and test validations remain blocking.

## Astra - Performance Regression

Runs on pull requests into main or via workflow_dispatch. Checks out the previous compatible
Build 3 commit and candidate in separate directories on one macOS runner and executes the
existing optimised Swift library-scaling benchmark at 1k, 10k and 50k bookmarks.
Reports raw text, JSON and Markdown with medians, p95 and percentage change.

These measurements do not fail a PR for timing changes because a shared runner
cannot guarantee stable hardware conditions. The tooling self-test, compilation
and malformed benchmark output still fail normally.

## Astra - Startup Performance

Runs on pull requests or manually. Builds an unsigned Release app, validates the
startup parser, then attempts five real launches using benchmark_startup.sh.
Stores CSV, human-readable summary and build/runtime logs. A successful
measurement requires the script's first-usable-window readiness markers.

Some GitHub-hosted macOS runners do not support reliable foreground app
interaction; failures to launch or measure are explicitly reported as unavailable
and do not fail the PR. Startup results are from a disposable runner profile,
not the user's restored browser data. They are not controlled cold-cache tests.

## Astra - WebKit Performance

Runs on pull requests or manually. Builds an unsigned Release app, then opens
a local HTTP fixture using Astra's existing URL-opening handler. Captures
webkit_benchmark.py snapshots of the Astra host process after initial launch,
one URL-open event and ten further URL-open events. The seven-second CPU
intervals and process-memory measurements are saved as JSON with a summary.

The tool only attributes the explicit Astra PID. WebKit XPC process identities
are listed separately rather than falsely counted as the browser's usage.
Consequently host RSS and physical footprint are not total WebKit memory or
per-tab measurements. URL dispatch is not proof of rendered page completion.
A runner unable to launch Astra explicitly reports the measurement unavailable.

## Interpretation and future gates

All three workflows upload available measurements to workflow artifacts, with
30-day retention. Each also writes the result or unavailability explanation to
the Actions job summary. Comparing results requires the same hardware, OS,
power mode, page fixture, build configuration and cache state.

Reliable blocking performance thresholds, end-to-end frame latency and
WebKit tab-specific memory measurements require a controlled dedicated Mac
runner and actual UI-driving instrumentation. The existing astra_workflow_report.py parses any available filtered CI unified-log
performance events into a separate JSON artifact. The parser is self-tested by
Release Metadata. Missing events are reported; collected internal durations do
not prove end-to-end input-to-first-frame latency.

For a controlled local run:

    bash scripts/benchmark_startup.sh /path/to/astra.app 8
    python3 scripts/webkit_benchmark.py scenarios
    python3 scripts/webkit_benchmark.py snapshot --pid ASTRA_PID --interval 30
    python3 scripts/astra_workflow_report.py /path/to/recorded.log --json
