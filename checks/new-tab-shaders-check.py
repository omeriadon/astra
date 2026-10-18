#!/usr/bin/env python3
"""Structural regressions for the built-in new-tab Metal presets.

Xcode/Metal compilation runs in validate-dither.yml. This check verifies that
all choices are still wired to the correct surface and use the Space palette.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
new_tab = (root / "astra/UI/Content/NewTabView.swift").read_text()
surface = (root / "astra/UI/Background/NewTabShaderSurface.swift").read_text()
metal = (root / "astra/UI/Background/NewTabShaderEffects.metal").read_text()

for value in ("smoke", "holographic", "ripple", "datamosh", "topographic"):
    assert f'backgroundStyle = "{value}"' in new_tab, f"missing picker: {value}"
    assert f'case .{value}:' in surface, f"missing rendering implementation: {value}"
for function in (
    "astraNewTabTexture",
    "astraSmokeReveal",
    "astraHolographicPrismatic",
    "astraLiveRipple",
    "astraDatamosh",
    "astraTopographic",
):
    assert f"[[ stitchable ]] half4 {function}(" in metal, function

# Prismatic is bar-only. Topographic owns its image source.
assert 'case "default", "solid", "image", "holographic": true' in new_tab
assert "preset != .holographic" in new_tab
assert "preset: .holographic, canAnimate: animatesBackground" in new_tab
assert ".fill(.ultraThinMaterial)" in new_tab
assert ".fill(.regularMaterial)" in new_tab
assert 'value("float", "blur")' in new_tab
assert "NewTabPointerTracker(pointer: ditherPointer)" in new_tab
assert "Choose Background Image" not in new_tab
assert "backgroundImagePath" not in new_tab
assert 'if backgroundStyle == "holographic" {' in new_tab

# Current Space colors and mesh positions, not a fixed backdrop or a bitmap.
assert "theme.meshColorPoints.prefix(4)" in surface
assert ".floatArray(locations)" in surface
assert ".colorArray(colors)" in surface
assert "spaceColor(" in metal
assert "if (preset == 3.0)" in metal  # monochrome holographic texture
assert "theme.appearanceMode" in surface

# No busy timers, and motion freezes cleanly when hidden/inactive.
assert "TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: !running))" in surface
assert "context.date.timeIntervalSinceReferenceDate" in surface
assert "scenePhase == .active" in surface
assert "clock.setRunning(false" in surface
assert "return isVisible && canAnimate && !reduceMotion" in surface
assert "float frame = floor(time * rate)" in metal
assert "float silver = 0.095" in metal
assert "if (preset == 3.0)" in metal
assert ".allowsHitTesting(false)" in surface
assert "Copyright (c) 2026 Kris Puckett" in metal

print("New-tab shader preset integration: OK")

# The dither viewport must consume pointer events above interactive controls
# without overriding hit testing, and must use the same timeline time base.
dither = (root / "astra/UI/Background/Dither/DitherBackground.swift").read_text()
dither_metal = (root / "astra/UI/Background/Dither/ThemeDither.metal").read_text()
assert "var canAnimate = true" in dither
assert "context.date.timeIntervalSinceReferenceDate" in dither
assert "event.window === window" in new_tab
assert "self?.track(event)" in new_tab
assert "float drift = time * wave.x * 12.0" in dither_metal
assert "float travelling = sin(" in dither_metal
assert "float3 litMesh = clamp(" in dither_metal
assert "float3 spectrum = " in metal
assert "float glint = pow(sweep, 5.0)" in metal
assert ".frame(maxWidth: .infinity, maxHeight: .infinity)" in new_tab
livable = (root / "Packages/Livable/Sources/Livable/Shaders/Livable.metal").read_text()
assert "float fold = sin(flowUV.x" in livable
assert "float halo = pow(" in livable
print("New-tab animation, materials and pointer checks: OK")
