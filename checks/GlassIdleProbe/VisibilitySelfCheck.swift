import Foundation

@main
struct VisibilitySelfCheck {
	static func main() {
		for mask in 0 ..< 16 {
			let appHidden = mask & 1 != 0
			let windowVisible = mask & 2 != 0
			let miniaturized = mask & 4 != 0
			let occlusionVisible = mask & 8 != 0
			let expected = mask == 10
			let actual = canRenderWindow(
				appHidden: appHidden,
				windowVisible: windowVisible,
				miniaturized: miniaturized,
				occlusionVisible: occlusionVisible
			)
			assert(actual == expected)
		}
		assert(ProbeMode.initialFromEnvironment([:]) == .plain)
		for mode in ProbeMode.allCases {
			assert(ProbeMode.initialFromEnvironment(["ASTRA_GLASS_PROBE_MODE": mode.rawValue]) == mode)
		}
		print("visibility predicate self-check passed")
	}
}
