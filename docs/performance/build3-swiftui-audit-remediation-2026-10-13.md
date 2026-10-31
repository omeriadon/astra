# Build 3 SwiftUI performance audit remediation — 2026-10-13

Base revision: `a84219d24e3f9fc6d903a2e6f85515d9b5c12e69` (Build 3).

## Changes

| Hot path | Remediation | Regression coverage |
| --- | --- | --- |
| Navigation chrome | Remove history-array/history-index `.id` identity changes; rely on controller Observation | `checks/swiftui-observation-performance-check.py` |
| Sidebar projection | Reuse favourites, pinned, normal, grouped, selection-order and index projections using a scalar structural revision; instrument cache misses as `sidebar.projection.resolve` | Static check, Xcode UI verification required |
| Sidebar observation | Avoid sending Control-Tab membership events on selection-only workspace changes | `checks/control-tab-observation-check.py` |
| Long sidebar lists | Use lazy pinned and normal tab sections inside the existing scroll view | Static check, native reorder/drag acceptance requires UI verification |
| Row hover previews | Mount geometry observations only while a row/tile is hovered; keep coordinates updated while scrolling | Static check, hover animation requires UI verification |
| Sidebar resizing | Keep native local drag updates at full frequency; coalesce parent window-width publications to approximately eight-point steps and commit exact width on drag release | Static check, drag and minimum-window-size verification required |
| Downloads chrome | Cache combined progress and selected icon against mutations of the download list | Static check, download UI and stale aggregate regression requires macOS run |
| AI streaming | Throttle parsing of the growing response/action snapshots; reconcile final message and final tool actions without duplicates | Static check, streaming/tool-call integration regression requires test |
| Reader startup | Prewarm the bundled scripts on a utility task at app entry while retaining synchronous script installation fallback for immediately-created WebViews | Static check, first-website Reader regression needed |
| WebKit host selection | Avoid building a full owned-tab index when the browser has no competing normal window; preserve multi-window ownership/media/capture rules | `checks/webkit-resource-policy-check.py` plus native multi-window tests |
| Sidebar edge blur | Use equatable gradient geometry, simplify blur overlays, respect Reduce Transparency | Static check, frame pacing and appearance comparison required |

## Existing optimizations preserved

- @Observable browser/controller/tab models and per-row Equatable boundaries.
- Existing WebKit warm-controller budget, process-lifetime and media/capture protection.
- Background persistence and download file workers.
- Hidden-download-list unmounting and download progress coalescing.
- Disabled-noise resource avoidance and reduced noise overscan.
- Existing tab/space transition and hover-preview visuals.

## Deliberately not changed without runtime evidence

- `BrowserSpacePager.swift` is not the active macOS sidebar composition at this revision. Replacing the current `ShellSpaceTabList` with this native pager would be a feature/interaction change, not a demonstrated performance fix.
- Eliminating the entire Haze mask/compositing path would change rendering. The overlay optimisations above preserve the effect; removal still requires controlled GPU/frame-pacing profiling with matching appearance and accessibility.
- The WebKit single-window fast path is implemented, but caching the live media/capture attachment set still requires validating background media, unsaved forms, popup state, capture, and cross-window reparenting. Caching a stale attachment set could break these invariants.
- Reader JavaScript now prewarms off-main; creating the first WebView before the task finishes still falls back to a synchronous read to guarantee the Reader detection script is installed before navigation. Its frequency and latency should be measured.

## Validation instructions

1. Run `python3 checks/swiftui-observation-performance-check.py` and `python3 checks/control-tab-observation-check.py` (added to the macOS debug workflow).
2. Run the macOS Debug Xcode 27 build with Swift 6.4 compiler settings of the base branch.
3. Test 10, 100, and 500-tab spaces: repeated selection, vertical scroll, reordering across pinned/normal/favourites, Today groups, hover previews while scrolling, and Control-Tab cycling.
4. Test divider resize continuously and at release; verify the exact final width and minimum-window-size behaviour.
5. Easel image IO/processing is intentionally out of scope (already fixed separately).
6. Test long AI streams with interleaved tool calls, final tool-call reconciliation, and cancellation.
7. Inspect `sidebar.projection.resolve` and `workflow.webview-hosts.resolve` timing logs during tab selection, grouped reorder, and window switching.
8. Check one-window and multiple-window WebKit ownership, Reader availability on first launch, and Reduce Transparency blur appearance.
9. Measure before/after with Instruments SwiftUI, Time Profiler, Core Animation and GPU capture at matched Release configurations.

## Evidence and limitations

Source-level structural assertions were evaluated against PR source. There was **no Xcode build, macOS runtime run, GPU profile, or quantitative before/after benchmark** available in the analysis environment. No runtime speedup is claimed until those tests pass.
