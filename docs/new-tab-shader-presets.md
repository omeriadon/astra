# New-tab Shader Presets

The background menu offers Default, Float, Theme Dither, Live Ripple, Datamosh,
and Topographic. Each effect is a fixed product preset at full effect opacity.
There are no parameter controls or image pickers. Topographic always uses the
built-in, deterministic procedural artwork; it never reads imported images.

| Preset | Fixed settings | Maximum scheduled rate |
| --- | --- | --- |
| Float | Speed 0.66, blur 63 points | 30 fps |
| Theme Dither | Speed 0.03, squares 7, spacing 0.77, corners 1.8, frequency 2.7, scale 0.3, five layers, levels 3.7, strength 0.21, contrast 1.88, brightness -0.5, minimum intensity 0, theme color 1 | 30 fps |
| Live Ripple | Amplitude 33, frequency 50, speed 2.3, damping 2.4, three rings | 30 fps |
| Datamosh | Corruption 0.015, smear 60, color bleed 0.95, glitch rate 0.7 | 30 fps |
| Topographic | Line count 17, width 0.06, color 0, animation 0.13 | 60 fps |

Dither cursor radius is 0.5, response 0.28, trail 0.7 seconds, fade 0.8 seconds,
and swirl 0.15. The internal octave amplitude remains 0.37. Black Space colors
receive a neutral exposure floor so animated squares remain visible, while zero
minimum intensity still allows truly black wave regions. Colors remain anchored
to the current Space mesh positions. Dither does not inherit mesh transparency.

Saved Smoke Reveal, Holographic, legacy image styles and unrecognized choices
migrate to Default. Previous parameter payloads and the imported Topographic
image selection are removed regardless of their payload type. The old image
files are no longer read. Migration is idempotent and retains valid style choices.

Only the displayed effect mounts a timeline. Animation clocks freeze on tab
switching, window minimization/occlusion, app inactivity, window focus loss and
Reduce Motion. The Dither pointer monitor mounts only while its animation is
active; it observes events above controls without consuming them. Float has a
30 fps scheduling cap, and Topographic now schedules up to 60 fps rather than 45.
The renderer may deliver fewer frames according to the display and system load.

## Licensing

Live Ripple and Datamosh adapt Kris Puckett's SwiftUIShaders (MIT); the complete
copyright and license notice remain in `NewTabShaderEffects.metal`.

## Validation

`checks/new-tab-shaders-check.py` checks routing, fixed uniforms, migration wiring,
Space palette propagation and lifecycle gates. `checks/dither-motion-check.swift`
checks clock pausing, cursor continuity and old-preference removal, including
invalid payloads and repeated migration. The Metal Dither CI workflow compiles
these Swift checks and compiles/links both Metal files on Xcode 27.

Mac acceptance still requires checking each effect at small/large window sizes,
light/dark/auto appearance, black/gray/colorful Spaces, cursor tracking above
search results, and pausing when switching tabs/windows, minimizing and enabling
Reduce Motion. Confirm Topographic cannot access previous imported artwork.
No GPU time, memory, battery, or visual measurements were made in this Linux
editing environment. Scheduling caps and lifecycle gates are implementation
constraints, not measured performance results.
