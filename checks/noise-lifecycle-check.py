"""Keep texture-backed noise dormant without altering theme mesh rendering."""
from pathlib import Path
surface = Path("astra/UI/Background/ThemeSurface.swift").read_text()
theme = Path("astra/Models/Spaces/BrowserTheme.swift").read_text()
assert "var shaderNoiseEnabled = false" in theme, "Default must remain noise-disabled"
assert "MeshGradientSurface(points: theme.meshColorPoints)" in surface
assert "if theme.shaderNoiseEnabled, theme.shaderNoiseAmount > 0" in surface
condition = surface.index("if theme.shaderNoiseEnabled, theme.shaderNoiseAmount > 0")
noise = surface.index("StableRandomNoise(")
assert condition < noise, "Noise renderer must be conditional on active visibility"
assert ".transition(.opacity)" in surface, "Keep the enable/disable opacity fade"
assert "value: theme.shaderNoiseAmount" in surface, "Keep continuous opacity adjustment"
assert "reduceMotion ? nil" in surface
print("Demand-driven noise renderer and visual transition checks passed")
