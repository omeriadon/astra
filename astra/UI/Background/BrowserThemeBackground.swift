import SwiftUI
#if os(macOS)
	import MaterialView
#endif

struct BrowserThemeBackground: View {
	let theme: BrowserTheme
	var spaces: [BrowserSpace] = []
	var scrollState: BrowserSpaceScrollState?
	@State private var paletteCache = (themes: [BrowserTheme](), colors: [[Color]]())
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

			SpaceThemeSurface(
				theme: theme,
				themes: spaces.map(\.theme),
				palettes: paletteCache.themes == spaces.map(\.theme) ? paletteCache.colors : [],
				scrollState: scrollState
			)
		}
		.task(id: spaces.map(\.theme)) {
			let themes = spaces.map(\.theme)
			let colors = await Task.detached(priority: .userInitiated) {
				themes.map { MeshGradientSurface.colors(for: $0.meshColorPoints) }
			}.value
			guard !Task.isCancelled else { return }
			paletteCache = (themes, colors)
		}
	}
}

private struct SpaceThemeSurface: View {
	let theme: BrowserTheme
	let themes: [BrowserTheme]
	let palettes: [[Color]]
	let scrollState: BrowserSpaceScrollState?
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var body: some View {
		let appearance = blendedAppearance
		ThemeSurface(
			theme: appearance.theme,
			colors: appearance.colors,
			noiseColorAmount: appearance.noiseColorAmount
		)
		.animation(scrollState == nil && !reduceMotion ? .smooth(duration: 0.3) : nil, value: theme)
	}

	private var blendedAppearance: (theme: BrowserTheme, colors: [Color]?, noiseColorAmount: Double?) {
		guard let rawPosition = scrollState?.position, !themes.isEmpty, palettes.count == themes.count else {
			return (theme, nil, nil)
		}
		let position = min(max(rawPosition, 0), Double(themes.count - 1))
		let firstIndex = Int(position)
		let secondIndex = min(firstIndex + 1, themes.count - 1)
		let progress = position - Double(firstIndex)
		let first = themes[firstIndex]
		let second = themes[secondIndex]
		var blended = first
		blended.meshOpacity = first.meshOpacity + (second.meshOpacity - first.meshOpacity) * progress
		let firstNoise = first.shaderNoiseEnabled ? first.shaderNoiseAmount : 0
		let secondNoise = second.shaderNoiseEnabled ? second.shaderNoiseAmount : 0
		blended.shaderNoiseEnabled = true
		blended.shaderNoiseAmount = firstNoise + (secondNoise - firstNoise) * progress
		let firstNoiseColor = first.shaderNoiseMonochrome ? 0.0 : 1.0
		let secondNoiseColor = second.shaderNoiseMonochrome ? 0.0 : 1.0
		let noiseColorAmount = firstNoiseColor + (secondNoiseColor - firstNoiseColor) * progress
		let colors = zip(palettes[firstIndex], palettes[secondIndex]).map { first, second in
			first.mix(with: second, by: progress)
		}
		return (blended, colors, noiseColorAmount)
	}
}
