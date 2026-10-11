# Arc sidebar and space animation investigation

Inspected 2026-10-11. Target: installed Arc 1.167.1 (88217), `/Applications/Arc.app/Contents/MacOS/Arc`, ARM64 slice. The initial investigation was read-only; the Ghidra and implementation follow-up is recorded below.

## Evidence and limits

REA opened the executable and inspected its Mach-O structure. Evidence `ev_a503fdc8d422fdffdc710cb30aab6787fd6695df400f6ca0f1db568bec82288a` identifies the universal executable SHA-256 as `6d0803e223992e9c950bfb66c997f13b48fb96f74187cc843c10924bb02ab9e4`. The exported REA record is `/tmp/astra-arc-rea-evidence.json`.

During the initial pass, REA's Ghidra, Hopper, and IDA providers were unavailable. REA dispatch inspection also rejected the executable because it exceeded its 64 MiB metadata input budget. The initial function-level findings came from local `llvm-objdump`, Objective-C metadata, and Swift descriptors. The follow-up adds direct Ghidra decompilation. No original Swift source was recovered and no live Arc execution was observed.

A fresh ARM64 extraction had SHA-256 `a8a759a852dfbdfa086d9906f6809f64cd12b4efff681848a951f3a17534ad53`, matching the existing `/tmp/astra-arc-scroll-research/Arc-arm64`. This permits reuse of that investigation's bounded disassemblies. New bounded disassemblies are `/tmp/arc-window-layout-bounded.asm` and `/tmp/arc-transition-layout.asm`. Addresses are unslid ARM64 virtual addresses. Stripped code can be printed under unrelated nearest-export labels; those labels do not establish ownership.

## Space switching: continuous native paging

The trace is:

```text
SidebarPagingContainerScrollView.scrollWheel:
  -> window content controller / next responder
  -> WindowViewController.scrollWheel:
  -> WindowLayoutController.pagingController
  -> PageSwipeController
  -> position / selection / settling callbacks
  -> sidebar presentation and layout
```

The scroll-view handler at `0x10025813c` forwards events. Its custom clip view's `constrainBoundsRect:` at `0x100258230` returns `documentVisibleRect`, rejecting the proposed native scroll rectangle. `WindowViewController` at `0x1002f3988` invokes the paging controller's vtable slot `0x288`, resolving to `0x100a1531c`. Together these establish custom gesture-driven paging rather than ordinary NSScrollView momentum paging.

Recovered mechanics, detailed in [the existing paging report](arc-space-paging-research.md):

| Mechanism | Native evidence |
| --- | --- |
| Lock horizontal input; reject vertical-dominant movement | `0x100a15b84–0x100a15b9c` |
| Accumulate finger motion as `offset -= deltaX * 0.5` | `0x100a1622c–0x100a16234` |
| Consume native momentum without additional displacement | `0x100a15f94`, `0x100a163a0–0x100a163b4` |
| Estimate velocity from recent 100 ms samples, in points/second | `0x100b135cc`, `0x100b1388c`, `0x100b13bec` |
| Choose nearest page below 5 points/second; directional destination otherwise | `0x100a17c94`, `0x100a18028`, `0x100a18174–0x100a1820c` |
| Adopt an interrupted spring's current presentation | `0x100a166f4`, `0x100a18ca8` |
| Seed release velocity only when it points toward the destination | `0x100a16604–0x100a16634` |
| Optional haptic feedback at page detents | `0x100a16f78` |

Dragging can traverse multiple spaces. At the edges, overshoot distance `d` becomes `255 * (1 - 1 / (d * 0.15 / 255 + 1))`; interrupted gestures use the inverse to preserve continuity (`0x100a14838`, `0x100a16864`).

Settling uses `Motion.SpringAnimation` / `Motion.SpringFunction`. Configuration selects 0.25 during gesture tracking, 0.4 otherwise, and a second value of 1.0 (`0x100a156c4–0x100a1570c`). Interpreting these as response and damping ratio is strongly supported by Swift field names and configuration arithmetic. Response is a spring parameter, not a guaranteed completion duration. The exact embedded Motion revision, refresh scheduling, and stopping tolerances remain unresolved.

## Sidebar presentation: layout plus a separate layer transform

Objective-C metadata identifies `WindowLayoutController` and its distinct fields: `effectiveSidebarWidth`, `floatingSidebarContainer`, `layoutState`, `sidebarTransitionState`, `sidebarResizeState`, `_isSidebarAnimating`, `_isTrackingOrAnimatingSidebarPages`, `currentSidebarAnimationUUID`, and a lazy `sidebarTransformAnimation`. This separates sidebar presentation from page tracking and resize state.

The lazy accessor at `0x100216dec` creates a **CABasicAnimation for `transform`**, stores it at the ivar identified by `0x1044cce90`, sets duration to zero, begin time to the largest finite Double, and `removedOnCompletion` to false. It also sets fill mode; its exact string was not resolved here.

The helper at `0x100219f9c` reads `layoutState`. One associated-value branch clamps a scalar `p` to 0...1, constructs a CATransform3D with X/Y scale `1 - 0.1*p`, and passes `26*p` as the X translation argument (`0x10021a1e8–0x10021a274`). These are composed transform operations; the resulting matrix translation need not equal the unscaled argument. It assigns the **same transform to fromValue and toValue**, then adds the animation to the sidebar view's layer (`0x10021a298`, `0x10021a2d4`, `0x10021a358`). Other branches remove that layer animation.

Observed: Arc has a reusable layer presentation override with scale and translation. Inference: it installs an externally computed pose instead of asking this CABasicAnimation to interpolate over time. Unknown: the exact user-facing meaning of this layout-state case. The 0.9 scale and 26-point argument must not be presented as universal sidebar show/hide constants.

Transition paths also move retained views between containers, toggle visibility, control autoresizing-mask translation, and request layout (`0x10021a3a4`, `0x10021af00`). One path explicitly runs `layoutSubtreeIfNeeded`, then CATransaction begin/flush/commit (`0x10021b398–0x10021b3bc`). This shows coordination between native layout and presentation; it does not prove every animation frame triggers a full layout.

## Item layout transitions

Arc ships `SidebarPagingContainerCollectionViewLayout`, an NSCollectionViewLayout subclass with a layout model, delegate, target collection view, and custom invalidation context.

It also ships `SidebarCollectionViewTransitionLayout`, holding `baseLayout`, `targetLayout`, `transitionProgress`, and `transitionSpring`. Its item-attribute helper at `0x100306460` reads frame geometry from both layouts and performs component interpolation using subtract/multiply/add operations at `0x10030666c–0x1003066a0`, before assigning the resulting frame. This is evidence for custom geometry interpolation, not simply replacing the list and fading it. The exact spring weighting of every frame component and which interactions choose this layout remain incomplete.

## Implications for Astra

Astra already implements most of the recovered space mechanics in `astra/UI/Shell/BrowserSpacePager.swift`: retained NSHostingView pages, native event handling, continuous pixel offsets, the edge formula and inverse, recent-sample velocity, directional selection, and an Apple Spring sampled by an NSView display link. It publishes fractional position to the theme background through BrowserSpaceScrollState. A rewrite or Motion dependency is unnecessary.

There are deliberate differences. Astra bounds incoming spring velocity to prevent overshooting the destination (`monotonicVelocity`); the inspected Arc release path only gates velocity by direction. Astra moves a clip view under its own control; Arc rejects native clip-view scrolling and routes presentation through custom layout. Neither difference alone establishes a performance defect. Astra's visible-page mounting limit is its own optimization, not a recovered Arc policy.

Before this follow-up, `BrowserSplitView.swift` retained a fixed-width sidebar and separately animated visibility and reserved content width, but its reveal used a mask without translating the leading sidebar. `DesktopBrowserShell.swift` supplied a 0.3-second smooth animation and guarded completion with a generation counter.

A similar presentation can be implemented within those existing components:

1. Keep the sidebar's internal layout at its final width. Derive mask, translation, and content reservation from explicit presentation progress, preserving the pinned-versus-overlay distinction.
2. Use one animation owner per transition. Apply immediate gesture updates and animate only settling; prevent a second implicit animation on child geometry.
3. Retarget from the currently displayed pose. Preserve velocity where supported, and invalidate obsolete completion work with the existing generation mechanism.
4. Keep WKWebView identity and page hosts stable. If measurement shows website relayout causes missed frames, separate the visual motion from the final viewport resize; this is a design option, not a verified Arc web-content strategy.
5. Keep Reduce Motion, hit testing, accessibility visibility, vertical scrolling, and window resizing tied to the same state.

The useful transfer is continuous presentation state plus coordinated geometry. Arc's recovered special-case transform constants should only be copied after its state case is identified. No new abstraction or animation library is needed to start.

## Coverage

Initial coverage: space input and settling were answered from matching binary artifacts. Sidebar transform and item geometry were identified, with user-facing branch mapping partial. The follow-up below resolves one floating-sidebar frame spring configuration; other sidebar modes and live frame pacing remain incomplete.

## Ghidra setup and verified follow-up

Ghidra 12.1.4 is installed at `/Users/omeriadon/Applications/ghidra_12.1.4_PUBLIC`. The official release archive was verified against SHA-256 `ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db`. Its missing macOS native decompiler was built from the bundled source for ARM64 using the existing compiler. Java 21 was reused.

REA provider readiness passed configuration, version, headless launcher, native executable architecture, and Java checks. `~/.codex/config.toml` now supplies `GHIDRA_INSTALL_DIR`, `JAVA_HOME`, and a 20-minute native startup deadline to REA. Its backup is `/Users/omeriadon/.codex/config.toml.before-ghidra-20261011-201245`. The old Ghidra MCP registration referenced deleted Downloads files; it was retained but disabled. The REA environment changes take effect when that MCP server starts again; this session's decompilation used Ghidra directly.

The first REA whole-program import reached analysis but failed because the disk filled. After disk space was cleared, a direct whole-program pass advanced further but reported unsupported Objective-C encodings, unresolved native references, and VarnodeContext address-space recovery errors. That broader pass was stopped. Whole-program autoanalysis is **not** claimed complete.

The bounded import and targeted decompilation succeeded. The reusable project is [ArcSidebarTrace.gpr](/Users/omeriadon/Documents/GhidraProjects/ArcSidebarTrace.gpr), containing `Arc-arm64`. Nine procedures were disassembled and decompiled, each with a nonempty body containing its entry and a successful decompiler result. The project saved successfully afterward. Pseudocode, scripts, assembly, and a manifest are preserved in `/Users/omeriadon/Documents/GhidraProjects/ArcSidebarTrace-evidence/`.

| Entry | Investigated role |
| --- | --- |
| `0x100216dec` | Reusable sidebar transform animation |
| `0x100219f9c` | Apply/remove sidebar transform pose |
| `0x100219358` | Window/sidebar/Home geometry calculation |
| `0x10021b4e0` | Floating-sidebar frame transition path |
| `0x100223fac` | AppKit frame-animation helper |
| `0x1002232a8` | Layout-state progress mapping |
| `0x100a01b9c` | Core Animation spring factory |
| `0x100a154c0` | Motion page-settling configuration |
| `0x100306460` | Collection item geometry interpolation |

These procedure roles are analyst descriptions, not recovered original Swift method names. Ghidra's Swift register/type recovery remains imperfect; assembly and stored metadata supply the corroboration for numerical and dispatch conclusions.

### Frame springs are separate from paging springs

The floating-sidebar path at `0x10021b4e0` passes the view from `WindowLayoutController.floatingSidebarContainer` into `0x100223fac`, selecting mode 5.

That helper saves the view's animation dictionary, installs CASpringAnimation entries for `frameOrigin` and `frameBounds`, begins an NSAnimationContext group, enables implicit animation, sets a completion handler, changes the frame, ends the group, and restores the dictionary. Its selector targets were decoded from native stubs. This is an AppKit/Core Animation frame mechanism, distinct from the Motion spring used for space paging.

The helper indexes two seven-entry Double tables:

| Mode | Response | Damping ratio |
| ---: | ---: | ---: |
| 0 | 0.25 | 0.9 |
| 1 | 0.35 | 0.9 |
| 2 | 1.25 | 0.9 |
| 3 | 0.15 | 0.95 |
| 4 | 0.28 | 0.63 |
| 5 | **0.18** | **0.8** |
| 6 | 0.08 | 0.8 |

Table addresses are `0x1036373e0` and `0x103637418`. The factory at `0x100a01b9c` reads CASpringAnimation mass and computes:

```text
stiffness = mass * (2*pi / response)^2
damping = mass * 4*pi * dampingRatio / response
duration = spring.settlingDuration
```

This resolves the parameter semantics. The decompiler alone misrepresented some floating-register values around Objective-C calls; the ARM64 instruction sequence and decoded `mass`, `setStiffness:`, `setDamping:`, and `settlingDuration` selectors establish the formulas. Mode 5 is verified for this floating-sidebar path; the meanings of the other modes are not all mapped.

Swift descriptors also resolve `WindowLayoutController.LayoutState` to `transitioning`, `home`, and `spaces`, and `SidebarTransitionState` to `none` and `hiddenToAnchoredPresentation`. The previously recovered 0.9-scale/26-point transform belongs to the transitioning LayoutState branch, so it was not applied to ordinary sidebar visibility.

## Reverted implementation attempt

The two animation edits below were reverted at the user's request. Both Swift files now match their pre-task source. The Ghidra setup and research artifacts were retained. The following records the attempted implementation and its checks, not Astra's current behavior.

- `BrowserSplitView.swift`: macOS now translates the retained full-width sidebar. Leading origin is `width * (visibility - 1)`; trailing origin is `viewportWidth - width * visibility`. Root clipping exposes the entering sidebar. The macOS shrinking mask was removed to avoid cropping the translated view twice. Content reservation continues to use its existing independent progress.
- `DesktopBrowserShell.swift`: macOS hover reveal/hide uses `.spring(response: 0.18, dampingFraction: 0.8)`, matching the recovered floating-sidebar calibration. Reduce Motion disables it. Existing iOS masking/timing, pinned-pane timing, window sizing, accessibility, hit testing, resize handling, and page retention remain in place.
- The existing Arc-derived space pager was retained.

Apple documents that this [SwiftUI spring preserves velocity when retargeted with another spring](https://developer.apple.com/documentation/swiftui/animation/spring%28response%3Adampingfraction%3Ablendduration%3A%29). Astra retains its existing normalized-progress clamping; this is not a claim of identical Core Animation overshoot or rendering.

Verification: leading/trailing hidden, visible, and intermediate geometry passed across several sidebar widths. A compiled platform check compared mass-normalized stiffness and damping from the recovered CASpringAnimation equations against `Spring(response: 0.18, dampingRatio: 0.8)`; they agreed. Xcode MCP compiled the changed files and reported `BUILD SUCCEEDED`. It also repeatedly reported a missing `astra.swiftdoc` during artifact copying even though the file exists; that diagnostic remains unresolved and was not hidden.

No live visual comparison, trackpad-feel check, or iOS build was performed. Exact visual equivalence, other Arc frame-animation modes, and complete whole-program type recovery remain unverified.
