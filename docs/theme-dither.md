# Theme dither

On macOS, select **Theme Dither** from the new-tab paint palette, then select
**Configure Dither**. The sheet renders a draft through the same native AppKit
`DitherMetalRenderer` used by the new-tab background. Save commits the draft;
Cancel leaves persisted settings unchanged.

The macOS new-tab background is an `NSViewRepresentable` backed by a click-through
`CAMetalLayer`. It does not use `TimelineView`, SwiftUI per-cell views, a WebView,
CPU noise generation, or texture readback. Pointer input is observed by the
native surface, so cursor movement does not rebuild the containing new-tab view.
The surface stops its timer when inactive, hidden, detached, or outside a
window. Wave time is accumulated across pauses. Reduce Motion disables wave,
intro reveal, and cursor interaction without changing stored preferences.

Theme mesh points and colors are passed per frame to the renderer. Theme colors
retain their positions and are spatially weighted by the shader. Custom palettes
are bounded to the renderer's supported eight colors and use discrete bands,
matching DesktopDither. Background style, color placement, and square style are
resolved into the effective render colors. The eight dither modes are Bayer,
Bayer 4, Bayer 2, Halftone, Lines, Crosshatch, Noise, and None.

Cursor settings include enablement, radius, strength, spring response, trail
duration, fade duration, and warp. The input path supplies the spring trail,
touch point, presence, radius, strength, and warp to both fused compute and
reference renderer paths. Positive speed is stored separately from compass
direction. Older negative speeds migrate once by rotating direction 180 degrees.

Codable decoding fills missing keys explicitly and maps legacy Astra
`gridSize`, `gridSpacing`, `colorLevels`, `waveScale`, and `animationEnabled`
values. Unknown style strings and nonfinite or out-of-range values resolve to
bounded defaults. Reloading a migrated configuration does not rotate it again.

The renderer retains the DesktopDither optimization set: shared immutable Metal
pipelines and gradient resources, fused field/cell compute, cached gradients,
GPU-private intermediate textures, coverage atlases, join-mask compute,
two-dimensional dispatch, adaptive cadence, top-strip Gaussian blur, and the
cell-aware blur fast path with MPS fallback. Renderer allocation guards cap
drawable dimensions and cell atlas sizes.

Validation includes Swift 6 typechecking of the renderer/native surface, motion
and persistence checks, and a Metal GPU differential smoke test that exercises
theme points, cursor input, fused compute, and the reference path. The GPU test compares 48 fixed-time 320×240 configurations across all eight modes,
three cell shapes, and theme/custom palettes against the reference renderer with
at most one channel-level difference. Cursor enable/disable checks verify that
input changes the output. Opaque and transparent cell-aware blur comparisons
allow at most two channel levels relative to MPS and require exact equality below
the blur strip. These are correctness checks, not Astra performance measurements.
Full-app builds and interactive browser appearance remain unverified locally.

The existing iOS SwiftUI shader and fixed preset remain available through
`DitherFallbackBackground`; AppKit code is compiled only on macOS.
