# Livable — Astra procedural variant

Derived from https://github.com/whatsinlab/livable at
`c8832f84cf83fe124983926d733a8ccb050c0cd5` (MIT; see LICENSE).
The upstream swirl, sheet warp, displacement and uniform generators are retained.

Astra-specific changes:

- `.livable(palette:isAnimated:speed:)` accepts four mesh points, each packed as
  `x, y, red, green, blue` (20 floats total).
- The Metal color effect generates its palette analytically. It has no
  `SwiftUI::Layer`, texture arguments, texture reads, or backdrop access.
- The input color supplies only silhouette alpha. Foreground controls are outside
  the effect. The custom-background search bar separately uses system material.
- No postprocess blur or mask render passes. The tonal field is smooth already.
- The timeline pauses when the caller disables animation, preserving phase.
  Reduced Motion renders a static phase. No frame cap or resolution reduction
  has been introduced without hardware measurements.

This API deliberately differs from upstream's source-image layer effect. Do not
replace the local package with an upstream dependency without porting these changes.
