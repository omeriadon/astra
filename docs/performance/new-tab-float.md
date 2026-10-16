# New tab Float and living search surface

## Behavior

The default background is sRGB (24.933, 24.933, 24.933)/255 in dark
appearance and (241.9, 242.06, 242.19)/255 in light appearance, both at 70%
opacity. Explicit space appearance overrides the system appearance.

The padded search bar is centered horizontally at about 20% of the content
height. Default animates its entrance on tab selection and runs Livable only
on the bar background. Float is the first built-in effect and runs Livable on
the page background. Float and custom images use the same bar with 50%-opacity
ultra-thin material; text and controls stay fully opaque. The palette menu
retains a chosen image when switching modes. Preferences retain existing images.

## Source efficiency audit

Upstream revision: c8832f84cf83fe124983926d733a8ccb050c0cd5.
Upstream uses a layer shader, source-layer texture reads for mask and virtual
sheets, then blur and masking. Astra's local MIT-licensed adaptation uses a
color shader with an explicit four-point space palette. It removes texture
reads and postprocess passes; it never samples a view or backdrop. The system
material in nondefault search bars remains a separate native material.

This is still substantial pixel work: a four-octave derivative noise field,
shared swirl/sheet transforms, directional sine fields, and up to three palette
evaluations (four exponential weights each) per pixel. Metal alone does not
prove low GPU cost. Float shades the full visible content at native resolution;
Default shades only the search background. Time-only swirl/transform terms
remain precomputed once per frame by upstream's uniform builder.

BrowserContentView constructs NewTabView only for displayed blank content.
It does not put a renderer in each saved tab or in KeepAliveWebStack. Fifty
saved blank tabs therefore do not mean fifty timelines. Window activity,
occlusion and miniaturization pause the visible page's timeline; disappearing
pages and Reduced Motion also stop ticking. iOS uses scene activity instead.
There are no timers or global animation state per saved tab. Timeline state is
contained inside the surface modifier, not the browser model or search list.

## Validation and measurement limits

Local checks: SwiftUI observation/performance and launch framework isolation
pass; project configuration parses after removing its permitted trailing commas;
whitespace validation passes. No Swift, Xcode, macOS, Metal device or GUI exists
on this Linux host. Native compilation, visual acceptance and CPU/GPU efficiency
have not been measured here. Compiler-safety validation cannot run without xcrun.
The normal macOS Debug Build CI is the native compilation check for this PR.

Required macOS acceptance:

1. Compare Default / Float / custom image in both appearances and two different
   space palettes, including a single-color space and a four-point mesh.
2. Check initial focus, typing, suggestions, arrow selection, Return and Escape;
   create successive tabs with Command-T and verify entrance and focus each time.
3. Switch between Default, Float and a photo; restart and verify selection.
4. Record CPU and Metal frame/GPU time in Release for 1 versus 50 saved blank tabs,
   keeping window size and the displayed mode identical. Compare Default, Float,
   and an image. Record device, display scale, refresh rate, CPU%, GPU time/frame,
   frame rate and energy impact. Do not infer numerical savings from source counts.
5. Repeat while viewing a website, minimizing the window, covering it completely,
   switching apps, and with Reduced Motion. Confirm animation timeline/frame
   submissions stop while paused and resume without a phase jump.
6. Only after profiling, consider lower rendering resolution or frame cadence
   if Float's full-page pixel cost warrants it. Neither is imposed in this change.
