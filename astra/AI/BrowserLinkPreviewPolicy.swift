import CoreGraphics
import Foundation

enum BrowserLinkPreviewPolicy {
	static func allows(
		mode: String,
		enabled: Bool,
		shiftOverride: Bool,
		shiftPressed: Bool,
		size: CGSize,
		sourceURL: URL?,
		configuration: BrowserSearchConfiguration = .default
	) -> Bool {
		guard size.width.isFinite, size.height.isFinite,
		      size.width > 0, size.height > 0, size.width < 100, size.height < 100
		else {
			return false
		}
		if shiftOverride, shiftPressed {
			return true
		}
		guard enabled else {
			return false
		}
		switch mode {
			case "always": return true
			case "search": return sourceURL.flatMap { configuration.query(for: $0) } != nil
			default: return false
		}
	}
}
