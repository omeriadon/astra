import SwiftUI

struct RandomNoiseEffect: ViewModifier {
	let isEnabled: Bool
	let intensity: Double
	let style: ThemeNoiseStyle

	func body(content: Content) -> some View {
		if isEnabled {
			content.visualEffect { view, proxy in
				view.colorEffect(
					ShaderLibrary.parameterizedNoise(
						.float2(proxy.size),
						.float(Float(intensity)),
						.float(Float(style.rawValue))
					)
				)
			}
		} else {
			content
		}
	}
}
