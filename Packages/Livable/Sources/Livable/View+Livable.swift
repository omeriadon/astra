import SwiftUI

public extension View {
	/// Applies Livable motion to a generated palette; never reads a source or backdrop texture.
	/// Palette contains four entries of x, y, red, green, blue (20 floats).
	func livable(palette: [Float], isAnimated: Bool = true, speed: Float = 0.8) -> some View {
		modifier(LivableViewModifier(palette: palette, isAnimated: isAnimated, speed: speed))
	}
}
