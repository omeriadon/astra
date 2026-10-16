#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Adapted from Kris Puckett's SwiftUIShaders (2026), MIT license.
// https://github.com/krispuckett/SwiftUIShaders
// Copyright (c) 2026 Kris Puckett.
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies,
// and to permit persons to whom the Software is furnished to do so, subject to
// the following conditions: The above copyright notice and this permission
// notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

namespace astra_newtab {
float hash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}
float noise(float2 p) {
    float2 cell = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(cell), hash(cell + float2(1, 0)), u.x),
               mix(hash(cell + float2(0, 1)), hash(cell + 1.0), u.x), u.y);
}
float fbm(float2 p, int octaves) {
    float result = 0.0, amplitude = 0.5;
    for (int i = 0; i < octaves; ++i) {
        result += noise(p) * amplitude;
        p *= 2.0;
        amplitude *= 0.5;
    }
    return result;
}
float3 spaceColor(float2 uv, device const float *points, int pointCount,
                  device const half4 *colors, int colorCount, float3 fallback) {
    float3 sum = float3(0.0);
    float weightSum = 0.0;
    for (int i = 0; i < min(min(pointCount / 2, colorCount), 4); ++i) {
        float2 delta = uv - float2(points[2 * i], points[2 * i + 1]);
        float weight = 1.0 / (dot(delta, delta) + 0.015);
        sum += float3(colors[i].rgb) * weight;
        weightSum += weight;
    }
    return weightSum > 0.0 ? sum / weightSum : fallback;
}
}

// Generate structured, multi-scale illustrations in Metal rather than shipping
// large bitmaps. The first three presets use the positioned Space mesh palette;
// the prismatic search-bar texture intentionally stays monochrome.
[[ stitchable ]] half4 astraNewTabTexture(
    float2 position, float2 size, float preset,
    device const float *points, int pointCount,
    device const half4 *colors, int colorCount, half4 fallback
) {
    using namespace astra_newtab;
    float2 uv = position / max(size, float2(1.0));
    float aspect = min(size.x / max(size.y, 1.0), 3.0);
    float2 p = float2(uv.x * aspect, uv.y);
    if (preset == 3.0) {
        // A few wide, smooth silver ribbons; no high-frequency hairlines or
        // scanlines behind glyphs. Keep the field dark enough for white text.
        float2 q = float2(p.x * 0.8, p.y * 1.5);
        float flow = fbm(q * 1.8 + 2.1, 3);
        float ribbon = sin(q.x * 7.0 + q.y * 2.0 + flow * 2.2);
        float silver = 0.07 + 0.24 * smoothstep(-0.55, 0.9, ribbon);
        silver += 0.05 * pow(max(ribbon, 0.0), 8.0);
        return half4(half3(silver), 1.0h);
    }
    float broad = fbm(p * 2.7 + 2.1, 4);
    float fine = fbm(p * 10.0 + broad * 3.0, 3);
    float2 warp = float2(fbm(p * 3.6 + float2(4.1, 0.8), 3),
                         fbm(p * 3.2 + float2(1.3, 7.7), 3)) - 0.5;
    float2 twisted = p + warp * (preset == 3.0 ? 0.26 : 0.17);
    float path = twisted.x * 1.8 + twisted.y * 0.72 + broad * 0.70;
    float ribbon = sin(path * 30.0 + fine * 7.0);
    float hairline = pow(clamp(1.0 - abs(ribbon), 0.0, 1.0), 12.0);
    float contour = 0.5 + 0.5 * sin(path * 11.0 + broad * 5.0);

    float3 theme = spaceColor(clamp(uv + warp * 0.14, 0.0, 1.0),
                              points, pointCount, colors, colorCount,
                              float3(fallback.rgb));
    float3 second = spaceColor(clamp(1.0 - uv + warp * 0.2, 0.0, 1.0),
                               points, pointCount, colors, colorCount,
                               float3(fallback.rgb));
    float3 result;
    float alpha = 1.0;
    if (preset == 0.0) {
        // Smoke: broad tinted clouds above the dark/light Space foundation,
        // threaded with crisp metallic veins.
        float mist = smoothstep(0.2, 0.83, broad + 0.25 * contour);
        result = mix(theme * 0.25, mix(theme, second, contour * 0.32),
                     0.36 + mist * 0.82);
        result += float3(0.50) * hairline * 0.42;
        alpha = 0.64 + 0.32 * mist;
    } else if (preset == 1.0) {
        // Ripple: shaded liquid strata, luminous crests and visible details
        // for displacement to refract. The palette stays spatially anchored.
        float shimmer = smoothstep(0.67, 0.97, contour);
        result = mix(theme * 0.28, theme * 1.17 + second * 0.22,
                     0.15 + contour * 0.8);
        result += float3(0.30) * (hairline * 0.75 + shimmer * 0.25);
    } else {
        // Datamosh: hard-edged theme bands + fine scanlines, so codec smear
        // and displaced channel samples remain legible at large window sizes.
        float bands = floor((uv.y + warp.y * 0.05) * 20.0) / 20.0;
        float glitches = step(0.64, noise(float2(floor(uv.x * 16.0), bands * 20.0)));
        float scan = 0.09 * sin(position.y * 1.2);
        result = mix(theme * (0.33 + contour * 0.8),
                     second * 1.18, glitches * 0.35);
        result += float3((hairline * 0.22) + scan);
    }
    result = clamp(result, 0.0, 1.0);
    return half4(half3(result * alpha), half(alpha));
}

// Smoke Reveal: adapted from bcs_smokeReveal. The fog itself is now tinted
// to the Space's light/dark companion color, not the upstream neutral grey.
[[ stitchable ]] half4 astraSmokeReveal(
    float2 position, SwiftUI::Layer layer, float2 size, float time,
    float amount, half4 fogColor
) {
    using namespace astra_newtab;
    float2 uv = position / max(size, float2(1.0));
    float2 smokeUV = uv * 5.0;
    float wx = fbm(smokeUV + float2(time * 0.45, time * 0.15), 3);
    float wy = fbm(smokeUV + float2(time * 0.15, -time * 0.3) + 5.2, 3);
    float density = fbm(smokeUV + float2(wx, wy) * 1.5
                       + float2(time * 0.22, time * 0.12), 4);
    density = clamp(density * density * amount * 1.5, 0.0, 1.0);
    float2 displaced = clamp(position + (float2(wx, wy) - 0.5) * 8.0 * density,
                             float2(0.0), size);
    half4 original = layer.sample(position);
    half4 sampled = layer.sample(displaced);
    float ray = (sin(uv.x * 8.0 + time * 0.3) * 0.5 + 0.5) *
                (1.0 - smoothstep(0.2, 1.0, uv.y)) * density * 0.1;
    half3 fog = half3(fogColor.rgb) +
                half3((noise(uv * 3.0 + time * 0.2) - 0.5) * 0.09 + ray);
    return half4(mix(sampled.rgb, fog * sampled.a, half(density)), original.a);
}

// Holographic / Prismatic: luminance-masked rainbow from bcs_holographic.
// The only consumer is the dedicated search-bar surface.
[[ stitchable ]] half4 astraHolographicPrismatic(
    float2 position, SwiftUI::Layer layer, float2 size, float time,
    float intensity, float scale, float speed, float angle
) {
    float2 uv = position / max(size, float2(1.0));
    half4 original = layer.sample(position);
    float phase = (uv.x * cos(angle) + uv.y * sin(angle)) * scale + time * speed;
    half3 rainbow = half3(sin(phase), sin(phase + 2.094), sin(phase + 4.189)) * 0.5h + 0.5h;
    float lum = dot(float3(original.rgb), float3(0.299, 0.587, 0.114));
    float mask = smoothstep(0.12, 0.40, lum);
    // Subtle broad spectral tint follows the few silver bands without
    // amplifying highlights or filling the whole field with rainbow detail.
    half3 result = mix(original.rgb, rainbow * 0.70h, half(intensity * mask));
    return half4(clamp(result, 0.0h, 1.0h), original.a);
}

// Live Ripple: radially displaced layered rings adapted from bcs_liveRipple.
[[ stitchable ]] half4 astraLiveRipple(
    float2 position, SwiftUI::Layer layer, float2 size, float time,
    float amplitude, float frequency, float speed, float damping, float rings
) {
    float2 uv = position / max(size, float2(1.0));
    float aspect = size.x / max(size.y, 1.0);
    float2 offset = float2(0.0);
    for (int i = 0; i < min(int(rings), 5); ++i) {
        float phase = float(i) * 1.256;
        float2 center = float2(0.5) + float2(
            sin(time * 0.3 + phase) * 0.05,
            cos(time * 0.4 + phase) * 0.05);
        float2 delta = uv - center;
        delta.x *= aspect;
        float dist = length(delta);
        float wave = sin(dist * frequency - time * speed + phase);
        float envelope = exp(-dist * damping);
        float2 dir = dist > 0.001 ? normalize(delta) : float2(0.0);
        dir.x /= aspect;
        offset += dir * wave * envelope * amplitude / max(rings, 1.0);
    }
    return layer.sample(clamp(position + offset, float2(0.0), size));
}

// Datamosh: block-level I-frame corruption and color channel bleed adapted
// from bcs_datamosh. The source is the Space-colored graphic above.
[[ stitchable ]] half4 astraDatamosh(
    float2 position, SwiftUI::Layer layer, float2 size, float time,
    float corruption, float smear, float bleed, float rate
) {
    using namespace astra_newtab;
    float2 cell = floor(position / 16.0);
    float frame = floor(time * rate);
    // Frame-to-frame changes are deliberate and perceptible. Smooth drift
    // inside each corrupted block avoids a completely frozen image between
    // successive codec updates.
    float randomValue = hash(cell * 0.73 + frame * 0.37);
    half4 original = layer.sample(position);
    if (randomValue < 1.0 - corruption) return original;
    float angle = hash(cell * 1.37 + floor(time * rate * 0.5) * 0.3) * 6.2831853;
    float2 displacement = float2(cos(angle), sin(angle)) *
                          smear * (0.5 + 0.5 * randomValue);
    displacement += float2(sin(time * 2.3 + cell.y * 0.2) * 13.0,
                           cos(time * 1.8 + cell.x * 0.15) * 5.0);
    half4 smudged = layer.sample(clamp(position + displacement, float2(0.0), size));
    half4 red = layer.sample(clamp(position + displacement * (1.0 + bleed * 0.3),
                                   float2(0.0), size));
    half4 blue = layer.sample(clamp(position + displacement * (1.0 - bleed * 0.2),
                                    float2(0.0), size));
    smudged.r = mix(smudged.r, red.r, half(bleed));
    smudged.b = mix(smudged.b, blue.b, half(bleed));
    smudged.rgb = floor(smudged.rgb * 16.0h) / 16.0h;
    float2 blockPos = fract(position / 16.0);
    float edge = 1.0 - step(0.03, min(blockPos.x, blockPos.y));
    smudged.rgb = clamp(smudged.rgb + half3(edge * 0.08), 0.0h, 1.0h);
    return smudged;
}
