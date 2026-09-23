#include <SwiftUI/SwiftUI_Metal.h>
#include <metal_stdlib>
using namespace metal;

float randomValue(float2 point) {
	return fract(sin(dot(point, float2(12.9898, 78.233))) * 43758.5453);
}

float valueNoise(float2 point) {
	float2 cell = floor(point);
	float2 fraction = fract(point);
	float2 blend = fraction * fraction * (3.0 - 2.0 * fraction);

	float lower = mix(
		randomValue(cell),
		randomValue(cell + float2(1.0, 0.0)),
		blend.x
	);
	float upper = mix(
		randomValue(cell + float2(0.0, 1.0)),
		randomValue(cell + float2(1.0, 1.0)),
		blend.x
	);
	return mix(lower, upper, blend.y);
}

[[ stitchable ]]
half4 parameterizedNoise(
	float2 position,
	half4 color,
	float2 size,
	float intensity,
	float style
) {
	float2 point = position / 0.05;
	point += float2(sin(time), cos(time)) * 0.5;

	float noise;
	if (style < 0.5) {
		noise = randomValue(floor(point));
	} else if (style < 1.5) {
		noise = valueNoise(point);
	} else {
		noise = (
			valueNoise(point * 0.5)
			+ valueNoise(point)
			+ valueNoise(point * 2.0) * 0.5
		) / 2.5;
	}

	float brightness = mix(0.7, 1.3, noise);
	float factor = mix(1.0, brightness, intensity);
	return half4(color.rgb * factor, color.a);
}
