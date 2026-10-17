# Arc sidebar paging

Inspected 2026-10-11: installed Arc 1.167.1, build 88217, ARM64 executable at `/Applications/Arc.app/Contents/MacOS/Arc`. This is static binary analysis, not recovered original Swift source. Addresses below are unslid virtual addresses for that executable.

## Recovered behaviour

Arc does not use native scroll-view paging for the sidebar. `SidebarPagingContainerScrollView.scrollWheel:` forwards to the window controller, which invokes a generic `PageSwipeController`. Its custom clip view rejects native scrolling by returning `documentVisibleRect` from `constrainBoundsRect:`.

| Behaviour | Binary evidence |
| --- | --- |
| Native wheel handling bypassed | `0x10025813c`, `0x100258230`, `0x1002f3988` |
| Precise gestures distinguished from wheel input | `0x100a1531c` |
| Vertical movement rejected when `abs(deltaY) > abs(deltaX)` | `0x100a15b84–0x100a15b9c` |
| Direct movement accumulates `scrollingDeltaX * -0.5` | `0x100a15f54`, `0x100a1622c–0x100a16234` |
| Native momentum consumed without further displacement | `0x100a15f94`, `0x100a163a0–0x100a163b4` |
| Release velocity uses recent 100 ms samples, in points/second | `0x100b135cc`, `0x100b1388c`, `0x100b13bec` |
| Release velocity cutoff is 5 points/second | `0x100a18028–0x100a18034` |
| Anchor is last page origin at or before current offset | `0x100a14928`, predicate `0x100a14a74` |
| Slow release chooses nearest origin | `0x100a18330`, comparator `0x100a1bb70` |
| Normal fast release chooses floor anchor plus 1 for positive velocity, floor anchor for negative velocity | `0x100a1801c`, `0x100a18194–0x100a181ac` |
| A gesture that interrupts settling uses floor anchor plus velocity sign | `0x100a18ca8`, `0x100a18174–0x100a18188` |
| Destinations clamped to page range | `0x100a181b4–0x100a1820c` |
| Release velocity seeded into spring only when directed toward destination | `0x100a16604–0x100a16634` |

Direct finger movement can traverse multiple pages. The release calculation is an additional directional decision from the current offset, not a one-page limit on the gesture.

At either edge, raw overshoot distance `d` is mapped to displayed overshoot:

```text
255 × (1 − 1 / (d × 0.15 / 255 + 1))
```

The inverse, used to adopt an interrupted presentation, is:

```text
255 × displayedOvershoot / (0.15 × (255 − displayedOvershoot))
```

These formulas are recovered from `0x100a14838` and `0x100a16864`. They prevent a hard stop at the first or last space.

## Spring configuration

The settling path configures `Motion.SpringAnimation`, whose `SpringFunction` fields include `response` and `dampingRatio`. It selects `0.25` while tracking a gesture, `0.4` otherwise, and a second parameter of `1.0` (`0x100a156c4–0x100a1570c`). Parameter interpretation is strongly supported by the stored field names and pi-based configuration arithmetic, rather than recovered source parameter labels.

The public [Motion SpringFunction source](https://github.com/b3ll/Motion/blob/main/Sources/Motion/Animations/Functions/SpringFunction.swift) has matching field names and response conversion. Its [SpringAnimation source](https://github.com/b3ll/Motion/blob/main/Sources/Motion/Animations/SpringAnimation.swift) handles the internal velocity sign conversion in its public setter. This supports using actual offset velocity, with its original sign, in Apple's spring API. The precise Motion revision embedded in Arc was not identified.

The implementation uses Apple's `Spring(response:dampingRatio:)`, sampled by an AppKit view display link. An assertion check compares its trajectory against the critically damped analytic equation at five times. That verifies the equation and velocity units, not every detail of Arc's animation environment or stopping tolerances.

## Astra implementation

`BrowserSpacePager.swift` now uses an AppKit container with a clipped document and retained `NSHostingView` pages on macOS. The container owns pixel offsets, gesture axis selection, edge resistance, release selection, and interruptible settling. It consumes horizontal gestures and their momentum without rewriting `NSEvent` or `CGEvent` objects. Vertical input and events outside the host pass through.

Page IDs, page-local view state, active-page accessibility, environment values, programmatic selection, Reduce Motion, viewport resizing, and fractional theme blending remain integrated with the existing browser. The iOS native SwiftUI pager remains in place.

## Verification and limits

- Xcode MCP application build passed.
- `checks/space-paging-check.swift` passed against the actual calculation enum: resistance and inverse adoption, release direction, multi-page travel, interrupted settling, edge clamps, stale velocity, critical spring trajectory, and convergence.
- A standalone AppKit probe compiled the actual pager with lightweight model fixtures and injected scroll events into its handler. It passed input consumption, horizontal momentum rejection, vertical passthrough, retained host identity, resizing, cancellation, long travel, edge resistance, programmatic retargeting, interrupted animation, and monitor/display-link teardown.
- Xcode's snippet runner crashed with a null-address access before producing a result. Standalone probes were used instead; this does not establish an application runtime crash.
- Human trackpad feel and visual equivalence to Arc remain unverified. Arc's complete original controller, haptic policy, animation environment, and exact stopping tolerances were not reproduced.

The bounded binary artifacts and detailed address notes are in `/tmp/astra-arc-scroll-research/`.

To rerun the calculation check against current production source:

```sh
python3 - <<'PY'
from pathlib import Path
source = Path('astra/UI/Shell/BrowserSpacePager.swift').read_text()
start = source.index('private enum BrowserSpacePagingPhysics')
end = source.index('\n\tprivate struct BrowserNativeSpacePager', start)
checks = Path('checks/space-paging-check.swift').read_text()
Path('/tmp/astra-space-paging-check.swift').write_text(
    'import SwiftUI\nimport Foundation\n' + source[start:end] + '\n' + checks
)
PY
xcrun swiftc /tmp/astra-space-paging-check.swift -o /tmp/astra-space-paging-check
/tmp/astra-space-paging-check
```
