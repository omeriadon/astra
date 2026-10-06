//
//  VariableBlur.metal
//  astra
//
//  Created by Adon Omeri on 6/10/2026.
//


#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

float blurRadius(float2 position, float fadeHeight, float maxRadius) {
    // max blur at y = 0
    // smoothly reaches zero at fadeHeight
    float amount = 1.0 - smoothstep(0.0, fadeHeight, position.y);
    return amount * maxRadius;
}

[[ stitchable ]]
half4 variableBlurHorizontal(
    float2 position,
    SwiftUI::Layer layer,
    float fadeHeight,
    float maxRadius
) {
    float radius = blurRadius(position, fadeHeight, maxRadius);
    float s = radius / 4.0;

    half4 result = half4(0.0);

    result += layer.sample(position + float2(-4.0 * s, 0)) * (1.0 / 256.0);
    result += layer.sample(position + float2(-3.0 * s, 0)) * (8.0 / 256.0);
    result += layer.sample(position + float2(-2.0 * s, 0)) * (28.0 / 256.0);
    result += layer.sample(position + float2(-1.0 * s, 0)) * (56.0 / 256.0);
    result += layer.sample(position)                         * (70.0 / 256.0);
    result += layer.sample(position + float2( 1.0 * s, 0)) * (56.0 / 256.0);
    result += layer.sample(position + float2( 2.0 * s, 0)) * (28.0 / 256.0);
    result += layer.sample(position + float2( 3.0 * s, 0)) * (8.0 / 256.0);
    result += layer.sample(position + float2( 4.0 * s, 0)) * (1.0 / 256.0);

    return result;
}

[[ stitchable ]]
half4 variableBlurVertical(
    float2 position,
    SwiftUI::Layer layer,
    float fadeHeight,
    float maxRadius
) {
    float radius = blurRadius(position, fadeHeight, maxRadius);
    float s = radius / 4.0;

    half4 result = half4(0.0);

    result += layer.sample(position + float2(0, -4.0 * s)) * (1.0 / 256.0);
    result += layer.sample(position + float2(0, -3.0 * s)) * (8.0 / 256.0);
    result += layer.sample(position + float2(0, -2.0 * s)) * (28.0 / 256.0);
    result += layer.sample(position + float2(0, -1.0 * s)) * (56.0 / 256.0);
    result += layer.sample(position)                         * (70.0 / 256.0);
    result += layer.sample(position + float2(0,  1.0 * s)) * (56.0 / 256.0);
    result += layer.sample(position + float2(0,  2.0 * s)) * (28.0 / 256.0);
    result += layer.sample(position + float2(0,  3.0 * s)) * (8.0 / 256.0);
    result += layer.sample(position + float2(0,  4.0 * s)) * (1.0 / 256.0);

    return result;
}