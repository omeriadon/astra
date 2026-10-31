import Foundation

nonisolated struct BrowserReaderAppearance: Codable, Equatable, Sendable {
	var font = Font.georgia
	var fontSize = 20.0
	var spacing = Spacing.standard
	var margins = Margins.standard
	var foreground = Palette.charcoal
	var background = Palette.paper

	enum Font: String, Codable, CaseIterable, Identifiable, Sendable {
		case georgia = "Georgia"
		case palatino = "Palatino"
		case system = "System"
		case monospaced = "Monospaced"

		var id: Self {
			self
		}

		var cssFamily: String {
			switch self {
				case .georgia: "Georgia, serif"
				case .palatino: "Palatino, 'Palatino Linotype', serif"
				case .system: "-apple-system, BlinkMacSystemFont, sans-serif"
				case .monospaced: "ui-monospace, Menlo, monospace"
			}
		}
	}

	enum Spacing: String, Codable, CaseIterable, Identifiable, Sendable {
		case compact = "Compact"
		case standard = "Standard"
		case relaxed = "Relaxed"

		var id: Self {
			self
		}

		var lineHeight: Double {
			switch self {
				case .compact: 1.4
				case .standard: 1.7
				case .relaxed: 2.0
			}
		}

		var letterSpacing: Double {
			switch self {
				case .compact: 0
				case .standard: 0.2
				case .relaxed: 0.6
			}
		}
	}

	enum Margins: String, Codable, CaseIterable, Identifiable, Sendable {
		case narrow = "Narrow"
		case standard = "Standard"
		case wide = "Wide"

		var id: Self {
			self
		}

		var padding: Int {
			switch self {
				case .narrow: 16
				case .standard: 24
				case .wide: 48
			}
		}

		var columnWidth: Int {
			switch self {
				case .narrow: 900
				case .standard: 680
				case .wide: 520
			}
		}
	}

	enum Palette: String, Codable, CaseIterable, Identifiable, Sendable {
		case black = "000000"
		case charcoal = "282724"
		case darkGray = "4b4b4b"
		case gray = "808080"
		case lightGray = "d6d6d6"
		case white = "ffffff"
		case paper = "faf9f6"
		case yellow = "f5e7b5"
		case sepia = "e3cfaa"
		case brown = "634632"

		var id: Self {
			self
		}

		var cssColor: String {
			"#\(rawValue)"
		}

		var title: String {
			switch self {
				case .black: "Black"
				case .charcoal: "Charcoal"
				case .darkGray: "Dark Gray"
				case .gray: "Gray"
				case .lightGray: "Light Gray"
				case .white: "White"
				case .paper: "Paper"
				case .yellow: "Soft Yellow"
				case .sepia: "Sepia"
				case .brown: "Brown"
			}
		}
	}

	var resolvedFontSize: Double {
		fontSize.isFinite ? min(max(fontSize, 14), 32) : 20
	}

	var styleSheet: String {
		"""
		:root { color-scheme: only light; background: \(background.cssColor); }
		body { color: \(foreground.cssColor); background: \(background.cssColor); padding-inline: min(\(margins.padding)px, 10vw); }
		main { max-width: \(margins.columnWidth)px; font-family: \(font.cssFamily); font-size: max(\(resolvedFontSize)px, \(resolvedFontSize / 17)em); line-height: \(spacing.lineHeight); letter-spacing: \(spacing.letterSpacing)px; }
		a { color: inherit; text-decoration: underline; }
		"""
	}
}
