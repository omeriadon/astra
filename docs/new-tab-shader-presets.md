# New-tab Shader Presets

The palette provides procedural Metal/SwiftUI effects and the translucent
Default background. Image imports and image loading have been removed; saved
legacy image styles render the Default foundation.

| Preset | Scope | Surface |
| --- | --- | --- |
| Smoke Reveal | Full new-tab page | Dark/light Space-color foundation with semi-transparent, marbled Space-color wisps and colored smoke |
| Holographic Prismatic | Search bar **only** | Brighter embossed silver ribbons and a moving diffraction spectrum; white text and placeholder |
| Live Ripple | Full new-tab page | Animated refraction over Space-mesh liquid; reduced to 56% opacity over the Default foundation |
| Datamosh | Full new-tab page | Hard-edged Space-mesh color strata with periodically smeared 16-point codec blocks and RGB bleed |

## Theme handling

The three full-page effects sample up to four current Space mesh points in
their original positions. The procedural source image uses inverse-distance
weights instead of choosing just the first Space color; its light/dark
foundation is derived from the Space appearance setting. Switching Space
recomputes the palette without copying or modifying a static image.

Holographic uses broad, animated spectral reflections over embossed metal,
without covering the search text with busy rainbow hairlines. The page behind it is Default, and its search text and prompt are
explicitly white. Default uses an ultraThinMaterial search bar; the other
full-page effects use regularMaterial at full strength.

Effects remain exclusive with Float and Theme Dither. Float retains its 30-point blur but uses exposure-corrected Space colours
and strong, drifting bright and dark folds. No effect loads a background image; the selected preset persists using
`astra.newTabBackgroundStyle`.

## Animation and interaction

Source artwork is deterministic and resolution-independent. The 45 fps holographic timeline
uses each frame's date as the shader clock. On macOS, the actual
window's activity and occlusion are authoritative, and animation time pauses
when the page becomes inactive or Reduce Motion is enabled.

Ripples remain continuous. Datamosh now updates codec blocks at 12 Hz and
drifts smoothly between updates. Dither's wave travels visibly, and a
non-consuming macOS pointer monitor tracks motion above the search field and
suggestions list without blocking controls. It is scoped to the Dither view.

## Upstream and licensing

Shaders adapt **Smoke Reveal, Holographic / Prismatic, Live Ripple and
Datamosh** from Kris Puckett's
[SwiftUIShaders](https://github.com/krispuckett/SwiftUIShaders), licensed MIT.
The upstream algorithms are selectively adapted to Astra's own generated
artwork and color-space theme model; the copyright and complete MIT permission,
warranty and liability notice appear at the top of
`astra/UI/Background/NewTabShaderEffects.metal`.
No entire upstream package or additional dependency is vendored.

## Validation

`checks/new-tab-shaders-check.py` checks picker routing, positioned Space
palette propagation, animation frame date, pointer tracking, material search
fields, bitmap removal, all five Metal entry points and attribution.
The existing `Astra - Metal Dither` workflow now checks that integration
and compiles/links the additional Metal source with Xcode 27.

**Mac acceptance steps**

1. Select every preset on an otherwise blank tab, then type in the search
   field; verify cursor and keyboard input remain uninterrupted.
2. Give two Spaces visibly different four-point color meshes and alternate
   between them in Smoke, Ripple and Datamosh. Check each background responds.
3. Switch between light/dark/auto Space appearance and confirm the Smoke
   foundation's contrast changes. Holographic must only change the search bar.
4. Confirm Float is visibly blurred, Default uses ultraThinMaterial, and
   no preset offers an image import or shows an image from old preferences.
5. Verify all shader presets visibly move while the window is active; move
   the cursor above controls in Dither and verify the delayed wake. Toggle
   Reduce Motion, minimize/occlude, switch tabs/Spaces and verify motion pauses.
6. Test large and small window sizes, full-screen, 100%/200% display scaling.
   Check the marbling and ripple edges for cropping, aliasing and readability.
7. Profile GPU Frame Capture, Energy Log and SwiftUI template at 30 fps,
   especially on integrated GPUs. Use the default background as an idle
   baseline. Do not infer performance wins from passing source checks.

Metal shader appearance, battery use and accessibility have not been
visually verified in this non-macOS execution environment.
