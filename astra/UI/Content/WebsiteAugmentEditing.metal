#include <metal_stdlib>
using namespace metal;

// Raster adaptation of AIEditingText.swift (be1933a7) and
// AITextRevealRenderer.swift (e270d30a), AppleIntelligenceForSwiftUI.
// https://github.com/alessiorubicini/AppleIntelligenceForSwiftUI
// Copyright (c) 2025 Alessio Rubicini
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

[[ stitchable ]] half4 astraWebsiteEditing(
    float2 position, half4 color, float2 size, float elapsed,
    float revealing, float dark
) {
    float2 uv = position / max(size, float2(1.0));
    float sourceAlpha = float(color.a);
    float3 original = float3(color.rgb) / max(sourceAlpha, 0.0001);
    float luminance = dot(original, float3(0.2126, 0.7152, 0.0722));
    // Unlike Text, a WKWebView snapshot has an opaque background. Estimate its
    // foreground coverage from contrast so the shimmer follows page details.
    float ink = saturate(mix(1.0 - luminance, luminance, dark));
    float3 background = float3(1.0 - dark);
    float3 dimmed = mix(background, original, 0.5);
    float highlight;
    float cover = 1.0;

    if (revealing < 0.5) {
        // Upstream: one page-height clear/white/clear gradient travels from
        // below the text to above it, linearly, every 1.2 seconds.
        float center = 1.5 - 2.0 * fract(elapsed / 1.2);
        highlight = max(0.0, 1.0 - 2.0 * abs(uv.y - center)) * ink;
    } else {
        // Upstream: 0.8 s Euclidean reveal from top-center, softness 0.12,
        // shimmer width 0.12, opacity 0.7, pulse 8 rad/s. Pixel coordinates
        // replace the TextRenderer's normalized (line,column) glyph grid.
        float progress = saturate(elapsed / 0.8);
        float distance = length(uv - float2(0.5, 0.0));
        float radius = progress * (length(float2(0.5, 1.0)) + 0.12);
        cover = smoothstep(radius - 0.12, radius, distance);
        float delta = abs(distance - radius);
        float pulse = 0.85 + 0.15 * sin(elapsed * 8.0);
        float shimmer = max(0.0, 1.0 - delta / 0.12) * pulse * 0.7;
        float ring = max(0.0, 1.0 - delta / 0.10) * 0.45;
        float reverseCenter = -0.5 + 2.0 * progress;
        float reverseShimmer = max(0.0, 1.0 - 2.0 * abs(uv.y - reverseCenter));
        highlight = saturate(shimmer + ring + reverseShimmer) * ink;
        // Finish completely transparent, including the optional ring fringe.
        highlight *= 1.0 - smoothstep(0.9, 1.0, progress);
    }

    float alpha = cover + (1.0 - cover) * highlight;
    float3 rgb = dimmed * cover * (1.0 - highlight) + float3(highlight);
    return half4(half3(saturate(rgb) * sourceAlpha), half(alpha * sourceAlpha));
}
