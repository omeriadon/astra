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

for value in ("smoke", "holographic", "ripple", "datamosh"):
    assert f'backgroundStyle = "{value}"' in new_tab, f"missing picker: {value}"
    assert f'case .{value}:' in surface, f"missing rendering implementation: {value}"
for function in (
    "astraNewTabTexture",
    "astraSmokeReveal",
    "astraHolographicPrismatic",
    "astraLiveRipple",
    "astraDatamosh",
):
    assert f"[[ stitchable ]] half4 {function}(" in metal, function

# Prismatic is bar-only; the page must stay default even when a custom
# image path is saved. Other effects must fill the background only.
assert 'case "default", "solid", "holographic": true' in new_tab
assert "preset != .holographic" in new_tab
assert "preset: .holographic, canAnimate: animatesBackground" in new_tab
assert 'if backgroundStyle == "holographic" {' in new_tab

# Current Space colors and mesh positions, not a fixed backdrop or a bitmap.
assert "theme.meshColorPoints.prefix(4)" in surface
assert ".floatArray(locations)" in surface
assert ".colorArray(colors)" in surface
assert "spaceColor(" in metal
assert "if (preset == 3.0)" in metal  # monochrome holographic texture
assert "theme.appearanceMode" in surface

# No busy timers, and motion freezes cleanly when hidden/inactive.
assert "TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !running))" in surface
assert "clock.setRunning(false" in surface
assert "!reduceMotion && scenePhase == .active" in surface
assert ".allowsHitTesting(false)" in surface
assert "Copyright (c) 2026 Kris Puckett" in metal

print("New-tab shader preset integration: OK")
