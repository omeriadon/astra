# New-tab Shader Presets

Adds four native Metal options to the existing new-tab palette menu. No WebView,
web content, download, network fetch, or bundled bitmap is required.

| Preset | Scope | Surface |
| --- | --- | --- |
| Smoke Reveal | Full new-tab page | Dark/light Space-color foundation with semi-transparent, marbled Space-color wisps and colored smoke |
| Holographic Prismatic | Search bar **only** | High-contrast black/grey/silver procedural streaks illuminated by moving luminance-masked prismatic bands |
| Live Ripple | Full new-tab page | Space-mesh-colored textured liquid with three concentric animated refraction sources |
| Datamosh | Full new-tab page | Hard-edged Space-mesh color strata with periodically smeared 16-point codec blocks and RGB bleed |

## Theme handling

The three full-page effects sample up to four current Space mesh points in
their original positions. The procedural source image uses inverse-distance
weights instead of choosing just the first Space color; its light/dark
foundation is derived from the Space appearance setting. Switching Space
recomputes the palette without copying or modifying a static image.

Holographic deliberately uses monochrome silver/black/white artwork so the
foil shader has a sharp luminance mask; this mode leaves the normal new-tab
page background in place, even if a custom background image was previously
saved. Its search text is white above a dark overlay for legibility.

Effects are mutually exclusive with Float, Theme Dither and uploaded images.
The picker preserves the path of any uploaded image while another mode is
active. The new preset is persisted in the existing
`astra.newTabBackgroundStyle` setting.

## Animation and interaction

The source artwork is deterministic and resolution-independent. Only the
chosen effect is rendered with a 30 fps timeline. The accumulated time pauses
when the view disappears, the window cannot animate, the app is inactive, or
Reduce Motion is on. Search-bar hit testing remains with its native TextField.

The ripples are continuous as in the upstream *Live Ripple* shader, not mouse-
triggered. The four presets do not change Dither's configurable cursor
interaction or its editor.

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

`checks/new-tab-shaders-check.py` checks picker routing, Space palette
propagation, all five Metal entry points, animation pausing and attribution.
The existing `Astra - Metal Dither` workflow now checks that integration
and compiles/links the additional Metal source with Xcode 27.

**Mac acceptance steps**

1. Select every preset on an otherwise blank tab, then type in the search
   field; verify cursor and keyboard input remain uninterrupted.
2. Give two Spaces visibly different four-point color meshes and alternate
   between them in Smoke, Ripple and Datamosh. Check each background responds.
3. Switch between light/dark/auto Space appearance and confirm the Smoke
   foundation's contrast changes. Holographic must only change the search bar.
4. Pick a custom image, choose Holographic, and return to the image option.
   The image must be retained and Holographic must not show it behind the bar.
5. Toggle Reduce Motion, minimize/occlude the browser, switch tabs/Spaces,
   then return. Time must be paused while inactive; no idle animation loops.
6. Test large and small window sizes, full-screen, 100%/200% display scaling.
   Check the marbling and ripple edges for cropping, aliasing and readability.
7. Profile GPU Frame Capture, Energy Log and SwiftUI template at 30 fps,
   especially on integrated GPUs. Use the default background as an idle
   baseline. Do not infer performance wins from passing source checks.

Metal shader appearance, battery use and accessibility have not been
visually verified in this non-macOS execution environment.
