# Sidebar paging diagnosis — 2026-10-11

## Evidence and limits

An approximately 35-second **Debug** Time Profiler recording of Astra at `ef3f7903` (uploaded by the tester) contained 12,859 running-thread samples, 12,243 on the main thread. The active 5–30 second window contained 12,130 main-thread samples; 5,961 (49.1%) included `NSHostingView.layout()`. These are inclusive CPU samples, **not counts of layout invocations or frame hitches**. About 1,092 full-recording main-thread samples included `BrowserNativeSpacePagerView.publishPosition`, and about 1,459 included `BrowserNativeSpacePagerView.render`. Inclusive categories cannot be added.

The stack under `NSClipView.scroll(to:)` includes `NSView translateOriginToPoint:`, `-[NSView _invalidateFocus]` and `NSViewHierarchyNoteGeometryInWindowDidChange`. The later window display cycle contains many `NSHostingView.layout()` / AttributeGraph samples and separate titlebar draggable-region work. This is a **plausible causal path**, not yet proof that every hosting layout comes from the clip movement.

A test with `ASTRA_PAGING_PROFILE_FREEZE_THEME=1` reduced theme publications from ~43/s to ~2/s but preserved high hosting layout counts (~116/s versus ~149/s in separately performed swipe intervals). Different gestures and backgrounds make these comparisons approximate; the test rules out theme publications as the *sole* cause, not every possible contribution.

## Baseline restoration

The detached-page root reuse experiment (commits `68d77c6`/`455238b`) was removed because it had no measured performance result and could produce stale page contents. The theme crossfade experiment (commits `8faa4f3`/`d95bab7`/`f495a1d`) was likewise removed: the test did not demonstrate that it addressed the dominant layout cost. Paging behaviour is back to the working baseline from `f495a1d` (with improved diagnostics), and the background is back to `ef3f7903`.

## Controlled testing

Launch in Xcode with `ASTRA_PAGING_METRICS=1`; leave all freeze flags OFF for baseline. Swipe normally for ~15 seconds and read:

```sh
log show --last 2m --style compact --predicate 'subsystem == "com.omeriadon.astra" AND eventMessage CONTAINS "paging.layout-sample"'
```

Use the following **separate** runs, with the same number, duration and style of swipe gestures and a freshly launched app:

1. **Baseline:** `ASTRA_PAGING_METRICS=1` only.
2. **Theme experiment:** add `ASTRA_PAGING_PROFILE_FREEZE_THEME=1` (background progress intentionally freezes).
3. **Viewport experiment:** remove the theme freeze and add `ASTRA_PAGING_PROFILE_FREEZE_VIEWPORT=1`. The gesture physics and theme progress still run but **the sidebar is deliberately stationary**. This mode is only for isolating scroll-driven AppKit work, **not** validating interaction or visual functionality. It is OFF by default.

New measurements: `host_layout_total_ms` (wall-time summed across observed page-host layout methods); `host_layout_max_ms`, `active_page_layouts`, `layout_near_clip_move` (timing correlation within 25ms, not proof of causation), `page_host_creations`, `page_root_replacements`, `native_update_calls`, `native_selection_changes` and `native_full_refreshes`. Recording counters add overhead; compare only identically instrumented runs. `page_window_updates` is a reconciliation count, **not** a count of mounted/unmounted pages.

Before enabling a production optimization, require: (1) matching Release configurations, (2) a repeated and controlled improvement in frame pacing or sampled main-thread cost, (3) no new toolbar/vertical-scroll/selection/hit-testing regression, and (4) verification of fast interruptions, themes, window resize and multiple spaces. This diagnostic patch **does not claim to fix the slowdown**.
