# Website-aware toolbar tint — research and implementation (October 2026)

## Existing Build 3 behaviour

`BrowserController` passed `WKWebView.themeColor` directly into the toolbar, otherwise used `WKWebView.underPageBackgroundColor` or white. The light/dark decision was an unweighted sum of RGB channels. `BrowserLoadingBar` used `BrowserTheme.progressColor` (maximum chroma from the *space* theme), which could disappear against the selected site's toolbar.

## Existing approaches researched

| Source | Technique | Applicability to Astra |
| --- | --- | --- |
| [MDN: meta theme-color](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/meta/name/theme-color) | Explicit per-page CSS colour, including media-dependent variants | Keep the native WebKit `themeColor` as an authoritative input when no convincing page header is visible |
| [MDN: web app theme_color](https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Manifest/Reference/theme_color) | Web-app manifest defines an optional theme preference, distinct from `<meta>` | Do not infer current visible chrome from the manifest; Apple's `WKWebView.themeColor` documentation specifically describes the first valid page meta tag |
| [Safari Color Tinting (andesco)](https://github.com/andesco/safari-color-tinting) | Empirical Safari 26+ research finds body backgrounds or qualifying full-width top-edge fixed/sticky elements, rather than only meta tags | Sample the current viewport's painted header/top-edge surfaces rather than hardcoding the brand domain |
| [Safari 26 investigations](https://grooovinger.com/notes/2026-02-27-safari-26-header-background) | Empirical comparison of meta theme and CSS header/background sampling | Confirms an explicit `<meta>` alone can diverge from the site's visible chrome |
| [branding-go](https://github.com/julianmarshall911/branding-go) | Scrapes CSS, boosts `--primary`/brand tokens, and ranks saturation/frequency | Useful for brand identity, but not reliable as the exact colour of the current page's toolbar, dark mode, route or scroll state |
| [Color Thief](https://github.com/lokesh/color-thief) | Image palette extraction / quantisation | Useful for a later image-logo/hero fallback, but requires image decoding and risks extracting incidental imagery |
| [Vibrant](https://github.com/Vibrant-Colors/node-vibrant) | Vibrant/muted image clusters | Same tradeoff; no need for a new JS bundle or image-worker pipeline for a solid-colour toolbar |
| [Brand Colors](https://github.com/reimertz/brand-colors) | Curated historical brand colour JSON | Company brand colours are not keyed to website routes, user's colour scheme or redesigns |
| [Simple Icons](https://github.com/simple-icons/simple-icons) | Thousands of brand icons with reference HEX values | Domain-to-brand mapping is ambiguous; icon HEX need not match currently visible site UI |
| [Apple WebKit themeColor](https://developer.apple.com/documentation/webkit/wkwebview/themecolor) | Native property reads the first valid theme-color meta tag | Use as a fallback to current on-screen header colours, even though Safari 26's own toolbar tinting may use a different source |
| [Apple WebKit underPageBackgroundColor](https://developer.apple.com/documentation/webkit/wkwebview/underpagebackgroundcolor) | Derives scrolling background from the body/html/webview backgrounds; is also publicly settable | Last fallback only: this may differ from a fixed/sticky page header |
| [W3C WCAG luminance](https://www.w3.org/WAI/WCAG21/Understanding/relative-luminance.html) | Linearised sRGB weighted luminance | Exact black-vs-white contrast choice with crossover luminance ≈ 0.179 |

**Decision:** No remote catalogue, domain allowlist, API or image-processing dependency. A local, bounded live surface sampler adapts to each actual page, its light/dark appearance, SPA changes, and sticky-header behaviour. Existing WebKit metadata remains in the priority chain.

## Implemented resolution order

1. **Visible website chrome:** in the page's isolated WebKit content world, inspect 40 hit-tested points across four shallow horizontal rows at the viewport top. Walk a maximum of 14 ancestors per point, compositing translucent computed backgrounds over opaque ancestors and accepting painted full-width headers, navbars and top-edge surfaces. A fully transparent header must not claim an opaque body colour as its own. Quantise RGB into small buckets and require at least 45% of all sampled points to agree on the dominant header colour. Transparent foreground controls do not obscure an opaque ancestor.
2. **Native WebKit theme colour:** respect `WKWebView.themeColor`, which accounts for page metadata and may update as a site's theme changes. Unlike scanning `<meta>` manually, this uses WebKit's own implementation.
3. **Visible page surface:** if no convincing header and no WebKit theme colour exist, accept an opaque surface only when it covers at least half the samples.
4. **Under-page background:** use WebKit's `underPageBackgroundColor`; otherwise white.

Non-solid image/gradient surfaces are deliberately not invented as one dominant solid colour. Samples are taken inside WebKit without network access, screenshot reads, RGB image decoding or full-stylesheet enumeration. The script limits updates to 750 ms or longer; mutations, viewport changes, scroll events and colour-scheme changes coalesce. Hidden pages do not sample. It only emits a message when the observed colour/source/URL changes. Navigation clears stored samples; every message is verified against the current main-frame URL and owning controller.

A website's visible solid header is intentionally prioritised above potentially stale `theme-color` metadata; the metadata wins over a generic white body. Users who prefer explicitly declared brand colours over currently visible header colours would require a separate policy setting; this PR does not introduce one.

## Loading indicator

The progress bar is solid black or solid white, chosen against the **actual top-bar colour** (or space fallback). The luminance calculation uses linearised sRGB with 0.2126 red + 0.7152 green + 0.0722 blue. White-to-black crossover follows equal WCAG contrast ratios at L ≈ sqrt(0.0525) - 0.05 ≈ 0.179. The visible progress track is 2pt high instead of 1.5pt.

## Behavioural validation

`node checks/website-chrome-tint-check.mjs` checks the injected script itself for: solid/translucent/fully transparent header handling, body fallback, gradient rejection, dynamic colour mutation, debounce, deduplication, hidden-tab suppression, duplicate-install protection, and the SwiftUI progress-colour wiring.

The JavaScript regression checks passed in an isolated V8 harness using the exact checked-in Swift script; GitHub Actions has not produced a run for this PR yet. The macOS WebKit runtime still needs a genuine Xcode build and interactive checks on representative sites. Test fixed vs sticky headers, gradients, responsive navigation, dark-mode transitions, SPA route changes, website apps and Mini Astra. The script does not claim pixel-accurate colour extraction for image/gradient headers; that would require a separate screenshot or image pipeline and profiling before adoption.

## Rejected shortcuts

- **Curated hostname → colour map:** easily stale, loses page-specific light/dark variants, adds upkeep and ambiguous hostname mapping.
- **Global CSS colour frequency or most saturated swatch:** often chooses button or ad colours unrelated to the toolbar, while requiring broad DOM/CSS traversal.
- **Favicon/hero quantisation on every navigation:** poorer correspondence to the visible page surface and unnecessary rendering, decoding and memory overhead.
- **Main-thread screenshot colour extraction:** risks WebKit paint/readback stalls and is inappropriate on the scrolling hot path.
