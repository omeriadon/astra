#include <metal_stdlib>
using namespace metal;

// Original Metal implementation inspired by the visual effect at reactbits.dev/backgrounds/dither.
// Value noise, octave warping, and ordered Bayer quantization; no React/WebGL runtime or source dependency.
namespace astra_dither {
float hash(float2 p) {
	float3 q = fract(float3(p.x, p.y, p.x) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(float2 p) {
	float2 cell = floor(p), f = fract(p);
	float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash(cell), hash(cell + float2(1, 0)), u.x),
		mix(hash(cell + float2(0, 1)), hash(cell + 1.0), u.x), u.y);
}

float clouds(float2 p, float frequency, float persistence, int octaves) {
	float sum = 0, amplitude = 1, total = 0;
	for (int i = 0; i < octaves; ++i) {
		sum += noise(p) * amplitude;
		total += amplitude;
		p = float2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8) * frequency + 7.3;
		amplitude *= persistence;
	}
	return sum / max(total, 0.001);
}

// Construct the standard 8x8 Bayer matrix from the cell's three least significant bits.
float bayer(int2 cell) {
	uint x = uint(cell.x) & 7, y = uint(cell.y) & 7, value = 0;
	for (uint bit = 0; bit < 3; ++bit) {
		uint xb = (x >> bit) & 1, yb = (y >> bit) & 1;
		value = value * 4 + ((xb ^ yb) * 2 + yb);
	}
	return (float(value) + 0.5) / 64.0 - 0.5;
}
}

[[ stitchable ]] half4 astraThemeDither(
	float2 position, float2 size, float time,
	float4 grid, float4 wave, float4 tones, float4 style, float4 cursor,
	half4 background,
	device const float *points, int pointCount,
	device const half4 *colors, int colorCount,
	device const float *trail, int trailCount
) {
	using namespace astra_dither;
	float height = max(size.y, 1.0);
	float pitch = grid.x + grid.y;
	float2 cell = floor(position / pitch);
	float2 center = (cell + 0.5) * pitch;
	float2 uv = (center - size * 0.5) / height;

	// Antialiased rounded squares. An actual point-sized gap is left between adjacent squares.
	float2 q = abs(position - center) - (grid.x * 0.5 - grid.z);
	float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - grid.z;
	float aa = max(fwidth(distance), 0.001);
	float coverage = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, distance);
	if (grid.y == 0.0 && grid.z == 0.0) coverage = 1.0;
	if (coverage <= 0.0) return background;

	float touch = 0.0;
	float2 warp = float2(0);
	for (int i = 0; i + 2 < min(trailCount, 24); i += 3) {
		float weight = trail[i + 2];
		float2 delta = (center - float2(trail[i], trail[i + 1])) / height;
		float reach = cursor.x * mix(0.55, 1.0, weight);
		float influence = weight * (1.0 - smoothstep(0.0, reach, length(delta)));
		touch = max(touch, influence);
		// Swirl around the smoothed head; its delayed samples contribute to erase/reveal only.
		if (i == 0) warp = float2(-delta.y, delta.x) * influence * cursor.z / max(reach, 0.001);
	}

	float2 p = (uv + warp) / wave.w;
	// Advance the domain and wave fronts independently. A zero speed freezes both.
	float drift = time * wave.x * 12.0;
	int octaves = int(style.w);
	float2 domain = float2(clouds(p - drift, wave.y, wave.z, octaves),
		clouds(p + float2(11.7, 3.4) - drift, wave.y, wave.z, octaves));
	float field = clouds(p + domain * 1.8, wave.y, wave.z, octaves);
	float travelling = sin(uv.x * 9.0 + uv.y * 5.5 + domain.x * 4.0
		- time * wave.x * 32.0);
	float crossWave = sin(uv.y * 7.0 - uv.x * 2.7 + domain.y * 5.0
		+ time * wave.x * 20.0);
	field += travelling * 0.17 + crossWave * 0.10;
	field = (field - 0.47) * tones.z * 1.27 + 0.53 + tones.w - touch * cursor.y * 0.75;
	float levels = max(tones.x - 1.0, 1.0);
	float quantized = floor(clamp(field + bayer(int2(cell)) * tones.y / levels, 0.0, 1.0) * levels + 0.5) / levels;
	quantized = clamp(quantized, 0.0, 1.0);
	float intensity = mix(style.x, 1.0, quantized);

	// Same inverse-square weights and 0.015 softness used to build Astra's 10x10 mesh.
	// Sampling the continuous field keeps colours anchored to their theme positions as waves move.
	float2 themeUV = clamp(center / max(size, float2(1)), 0.0, 1.0);
	float3 mesh = float3(0);
	float totalWeight = 0.0;
	for (int i = 0; i < min(min(pointCount / 2, colorCount), 4); ++i) {
		float2 delta = themeUV - float2(points[i * 2], points[i * 2 + 1]);
		float weight = 1.0 / (dot(delta, delta) + 0.015);
		mesh += float3(colors[i].rgb) * weight;
		totalWeight += weight;
	}
	mesh = totalWeight > 0.0 ? mesh / totalWeight : float3(0.5);
	float3 base = float3(background.rgb);
	// Expose dark Space colours without replacing their hue.
	float peak = max(mesh.r, max(mesh.g, mesh.b));
	float gain = mix(2.85, 1.2, smoothstep(0.12, 0.85, peak));
	float3 litMesh = clamp(mesh * gain + float3(0.24), 0.0, 1.0);
	float3 tint = mix(float3(1.0), litMesh, style.y);
	float highlight = pow(smoothstep(0.55, 0.98, quantized), 2.0);
	float3 litSquare = clamp(tint * (intensity + highlight * 0.14), 0.0, 1.0);
	float3 square = mix(base, litSquare, style.z);
	return half4(half3(mix(base, square, coverage)), 1.0h);
}
