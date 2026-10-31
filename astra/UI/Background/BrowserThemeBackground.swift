import SwiftUI
#if os(macOS)
	import MaterialView
#endif

struct BrowserThemeBackground: View {
	let theme: BrowserTheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	#if os(macOS)
		private static let blurStyle = NSMaterialView.Effect.MaterialStyle(
			backgroundColor: .clear,
			saturationFactor: 1,
			brightnessFactor: 0,
			blurRadius: 40
		)

		private static let windowEffect = NSMaterialView.Effect(
			active: blurStyle,
			inactive: blurStyle,
			emphasized: blurStyle
		)

		private struct WindowMaterial: NSViewRepresentable {
			func makeNSView(context _: Context) -> NSMaterialView {
				let view = NSMaterialView()
				// Window configuration runs when the view attaches, before later SwiftUI updates.
				view.isContentView = true
				view.state = .active
				view.scale = 1
				view.reduceTransparencyOverride = false
				view.increaseContrastOverride = false
				view.effect = BrowserThemeBackground.windowEffect
				return view
			}

			func updateNSView(_: NSMaterialView, context _: Context) {}
		}
	#endif

	var body: some View {
		ZStack {
			#if os(macOS)
				WindowMaterial()
					.allowsHitTesting(false)
					.accessibilityHidden(true)
			#else
				Color.gray
			#endif

			ThemeSurface(theme: theme)
				.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: theme)
		}
	}
}
