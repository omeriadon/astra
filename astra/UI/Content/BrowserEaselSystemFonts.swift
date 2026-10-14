import SwiftUI
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
			case .newYork: .system(size: size, design: .serif)
			default: .custom(font.rawValue, size: size)
		}
	}

	#if os(macOS)
		static func appKitFont(for font: BrowserEaselDocument.Item.Font, size: CGFloat) -> NSFont {
			switch font {
				case .sfMono:
					return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
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
