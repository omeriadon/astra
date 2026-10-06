// Compile with BrowserReaderAppearance.swift, then run the resulting executable.
import Foundation

@main
struct ReaderAppearanceChecks {
	static func main() throws {
		let defaults = BrowserReaderAppearance()
		precondition(defaults.foreground == .charcoal && defaults.background == .paper)
		precondition(defaults.styleSheet.contains("#282724"))
		precondition(defaults.styleSheet.contains("#faf9f6"))

		var appearance = defaults
		appearance.font = .monospaced
		appearance.fontSize = 28
		appearance.spacing = .relaxed
		appearance.margins = .wide
		appearance.foreground = .white
		appearance.background = .brown
		let data = try JSONEncoder().encode(appearance)
		let decoded = try JSONDecoder().decode(BrowserReaderAppearance.self, from: data)
		precondition(decoded == appearance)
		precondition(appearance.styleSheet.contains("ui-monospace"))
		precondition(appearance.styleSheet.contains("line-height: 2.0"))
		precondition(appearance.styleSheet.contains("max-width: 520px"))
		precondition(appearance.styleSheet.contains("#ffffff"))
		precondition(appearance.styleSheet.contains("#634632"))

		for font in BrowserReaderAppearance.Font.allCases {
			appearance.font = font
			precondition(appearance.styleSheet.contains(font.cssFamily))
		}
		for palette in BrowserReaderAppearance.Palette.allCases {
			precondition(palette.rawValue.count == 6 && Int(palette.rawValue, radix: 16) != nil)
		}
		precondition(Set(BrowserReaderAppearance.Spacing.allCases.map(\.lineHeight)).count == 3)
		precondition(Set(BrowserReaderAppearance.Margins.allCases.map(\.columnWidth)).count == 3)
		appearance.fontSize = .nan
		precondition(appearance.resolvedFontSize == 20)
		appearance.fontSize = -100
		precondition(appearance.resolvedFontSize == 14)
		appearance.fontSize = 1000
		precondition(appearance.resolvedFontSize == 32)
		print("Reader appearance defaults, persistence, presets, and size bounds passed.")
	}
}
