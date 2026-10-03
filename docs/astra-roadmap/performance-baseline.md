# Astra performance baseline protocol

No performance numbers in this document are claimed as measured. Record results only after running the exact scenario on the user's Mac with the build/configuration identified below.

## Required metadata

Record: Mac model and memory, macOS build, Xcode/build configuration, Astra marketing/build version and commit, WebKit framework build, power mode, whether Instruments was attached, network type, tab count, loaded versus hibernated tab count, and whether any tab had media/PiP/capture/unsaved form state.

## Startup

1. Quit Astra after a clean persisted normal session with 1, 10, 50 and 100 tabs.
2. Measure from process launch to the first usable browser window and separately to selected-page load completion.
3. Repeat five times per tab count, discarding no outlier without recording why.
4. Compare like-for-like Debug/Release results separately. Do not compare a warm WebKit/process cache run with a cold run as if they are equivalent.

## Tab switching

1. Prepare ten normal tabs: five loaded, five hibernated. Include one media page only in a separate media scenario.
2. Measure selection request to first rendered destination frame for loaded-to-loaded, loaded-to-hibernated and hibernated-to-loaded transitions.
3. Repeat switching across spaces and pinned/favourite/normal locations.
4. Verify MRU/order state and controller ownership are unchanged after measurement.

## Memory per tab

1. Capture app, WebContent and Network process resident memory after a stable 30-second idle period at 1, 10, 25, 50 and 100 tabs.
2. Record loaded/hibernated counts and page class; do not report a single “memory per tab” number across mixed workloads.
3. Repeat after an OS memory warning/pressure event and record which tabs were eligible for hibernation.
4. PiP, camera/microphone capture, active downloads and unsaved form state must remain protected from destructive optimization.

## Slow/large page scenarios

Use a fixed local fixture or immutable test URL supplied at runtime. Measure navigation start/commit/finish separately, page responsiveness after commit, favicon/snapshot work and persistence activity. Do not collect page text, form content, query strings or credentials in diagnostic output.

## Optimization rule

Do not change pooling, prewarming, live-view limits, favicon bounds, snapshot cadence or persistence scheduling solely from source inspection. A change must name the measured regression, baseline, post-change measurement and lifecycle/privacy invariants it preserves.
