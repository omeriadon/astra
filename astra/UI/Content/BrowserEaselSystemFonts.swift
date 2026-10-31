import SwiftUI
import CoreText
#if os(macOS)
	import AppKit
#endif

/// Preserve saved Easel font identifiers while resolving Apple's system fonts
/// through their public font-design APIs rather than bundling proprietary files.
@MainActor
enum BrowserEaselSystemFonts {
	static func swiftUIFont(for font: BrowserEaselDocument.Item.Font, size: CGFloat) -> Font {
		switch font {
			case .sfMono: .system(size: size, design: .monospaced)
			case .sfCompactRounded:
				if compactRoundedFontIsAvailable {
					.custom(font.rawValue, size: size)
				} else {
					.system(size: size, design: .rounded)
				}
			case .newYork: .system(size: size, design: .serif)
			default: .custom(font.rawValue, size: size)
		}
	}

	static func displayName(for font: BrowserEaselDocument.Item.Font) -> String {
		if font == .sfCompactRounded, !compactRoundedFontIsAvailable {
			return "SF Compact Rounded (SF Pro Rounded fallback)"
		}
		return font.displayName
	}

	/// SF Compact Rounded is exposed on some Apple OS versions and device families.
	/// Check the actual PostScript face before selecting it so older systems use
	/// Apple's rounded system design instead of silently substituting a different face.
	static var compactRoundedFontIsAvailable: Bool {
		let expectedName = BrowserEaselDocument.Item.Font.sfCompactRounded.rawValue
		let resolvedFont = CTFontCreateWithName(expectedName as CFString, 12, nil)
		return CTFontCopyPostScriptName(resolvedFont) as String == expectedName
	}

	#if os(macOS)
		static func appKitFont(for font: BrowserEaselDocument.Item.Font, size: CGFloat) -> NSFont {
			switch font {
				case .sfMono:
					return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
				case .sfCompactRounded:
					if let compactRounded = NSFont(name: font.rawValue, size: size) {
						return compactRounded
					}
					let system = NSFont.systemFont(ofSize: size)
					guard let descriptor = system.fontDescriptor.withDesign(.rounded) else { return system }
					return NSFont(descriptor: descriptor, size: size) ?? system
				case .newYork:
					let system = NSFont.systemFont(ofSize: size)
					guard let descriptor = system.fontDescriptor.withDesign(.serif) else { return system }
					return NSFont(descriptor: descriptor, size: size) ?? system
				default:
					return NSFont(name: font.rawValue, size: size) ?? .systemFont(ofSize: size)
			}
		}
	#endif
}
