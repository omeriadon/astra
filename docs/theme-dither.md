# Theme dither

Choose **Use Theme Dither** from the new-tab paint palette. **Configure Dither…**
opens live controls; changes persist between launches. Existing image/plain
backgrounds remain available. This is opt-in; the sidebar and selected tab materials
are unchanged.

```swift
DitherBackground(
    theme: browser.theme,
    configuration: DitherConfiguration(
        gridSize: 4,
        gridSpacing: 1,
        cornerRadius: 1,
        waveSpeed: 0.055,
        waveFrequency: 4.1,
        waveAmplitude: 0.37,
        colorLevels: 5.4,
        cursorInteractionEnabled: true,
        cursorRadius: 0.6,
        cursorResponse: 0.28,
        cursorTrailDuration: 0.45
    )
)
```

Every input has a description, units, and reasonable range immediately above its
declaration in `DitherConfiguration.swift`. `DitherControls` is an optional editor
for the same configuration. Square size excludes spacing; corner radius is capped
at half the square size. Grid dimensions use SwiftUI points, not physical pixels.

New dither defaults add visible cell separation, faster wave motion and higher
contrast. Previously saved configurations remain compatible; the revised
shader also boosts dark theme colours for those configurations.

The original Metal fill is visually inspired by
https://reactbits.dev/backgrounds/dither?waveSpeed=0.02&waveAmplitude=0.37&waveFrequency=4.1&colorNum=5.4&mouseRadius=0.6
and uses value-noise domain warping and Bayer quantization. It is not a pixel-exact
port: it uses its own noise field and animated cursor model. There is no copied
React/WebGL source or added dependency.

Theme colours retain their positions: the shader interpolates the current space's
up to four points with the same inverse-square weights and 0.015 softness as
`MeshGradientSurface.colors(for:)`. It evaluates that field continuously rather
than interpolating SwiftUI's sampled 10x10 mesh, so tiny interpolation differences
are expected. Mesh opacity is respected; gaps use the theme's light/dark appearance.

The cursor uses a critically damped spring with preserved velocity on retargeting.
Eight delayed samples create a trailing wake. Presence fades on entry/exit;
positive strength erases waves, negative strength reveals them. Swirl displaces the
noise around the smoothed cursor. `cursorResponse`, `cursorTrailDuration`, and
`cursorFadeDuration` control separate aspects of the motion. Reentry starts at the
new cursor location without a sweep across the window.

For backgrounds beneath controls, share a `DitherPointerInput` with the containing
view and update its `location` in that ancestor's `onContinuousHover`. Read it only
inside the background: pointer writes then avoid rebuilding the containing view.
`NewTabView` uses this arrangement so hover works over the search field and list.
Standalone backgrounds track their own hover. No click/drag gesture is installed,
so foreground buttons, text selection, and scrolling keep their normal gestures.

The frame clock is local to the background, defaults to 45 fps, and pauses while
offscreen, inactive, manually disabled, or under Reduce Motion. Resume preserves
wave time. Disabling animation or Reduce Motion also removes cursor motion.
Only the effect subtree receives frame updates. One Metal fill draws the grid;
there is no per-cell SwiftUI hierarchy, CPU noise generation, or GPU readback.
Large displays, high octave counts, and high refresh rates still need profiling
on the target Mac; these are quality controls, not a performance guarantee.

Validation: `Astra - Metal Dither` compiles/links the actual shader and exercises
spring continuity, frame-rate independence, exit/reentry, clock suspension,
configuration clamping, and persistence on macOS. The standard macOS Debug build
checks SwiftUI integration. Actual appearance, pointer routing, and GPU cost need
an interactive macOS run; Linux cannot validate those.
