import CoreText
import Foundation
#if os(macOS)
	import AppKit
#else
	import UIKit
#endif

/// Model geometry is updated at edit boundaries, never during SwiftUI measurement.
/// Only the edited text is shaped; unrelated easel items keep their existing layout.
@MainActor
enum EaselTextLayout {
	static let padding: CGFloat = 8
	static let viewportMargin: CGFloat = 48

	static func fit(_ item: inout BrowserEaselDocument.Item, viewportWidth: CGFloat) {
		guard item.kind == .text else { return }
		#if os(macOS)
			let font = BrowserEaselSystemFonts.appKitFont(for: item.font, size: CGFloat(item.size.rawValue))
		#else
			let size = CGFloat(item.size.rawValue)
			let system = UIFont.systemFont(ofSize: size)
			let design: UIFontDescriptor.SystemDesign
			switch item.font.rawValue {
				case "SFMono-Regular": design = .monospaced
				case "NewYorkSmall-Regular": design = .serif
				case "SFCompactRounded-Regular": design = .rounded
				default: design = .default
			}
			let fallback = system.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: size) } ?? system
			let font = UIFont(name: item.font.rawValue, size: size) ?? fallback
		#endif
		if item.textWidthIsFixed == false {
			// Typographic advance includes trailing spaces, so the box grows with
			// every character rather than waiting for the next visible glyph.
			let naturalWidth = item.text.components(separatedBy: .newlines).reduce(CGFloat.zero) { width, paragraph in
				let attributed = NSAttributedString(string: paragraph, attributes: [.font: font])
				let line = CTLineCreateWithAttributedString(attributed)
				return max(width, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
			}
			let limit = min(10000, max(32, viewportWidth - viewportMargin))
			item.width = min(limit, max(32, ceil(naturalWidth) + padding * 2))
		}
		let storage = NSTextStorage(string: item.text, attributes: [.font: font])
		let layout = NSLayoutManager()
		let container = NSTextContainer(size: CGSize(width: max(1, item.width - padding * 2), height: 3_000_000))
		container.lineFragmentPadding = 0
		storage.addLayoutManager(layout)
		layout.addTextContainer(container)
		layout.ensureLayout(for: container)
		let lineHeight: CGFloat
		#if os(macOS)
			lineHeight = layout.defaultLineHeight(for: font)
		#else
			lineHeight = font.lineHeight
		#endif
		let height = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
		item.height = ceil(max(lineHeight, height)) + padding * 2
	}
}
