// Run: swiftc astra/Models/Search/BrowserSearchConfiguration.swift astra/AI/BrowserLinkPreviewPolicy.swift checks/hover-preview-policy-check.swift -o /tmp/astra-hover-preview-check && /tmp/astra-hover-preview-check
import CoreGraphics
import Foundation

@main
struct HoverPreviewPolicyCheck {
	static func main() {
		let page = URL(string: "https://example.com/article")!
		let search = URL(string: "https://www.google.com/search?q=swift")!
		func allows(_ mode: String, source: URL? = page, size: CGSize = CGSize(width: 99, height: 99), shift: Bool = false, override: Bool = false, enabled: Bool = true) -> Bool {
			BrowserLinkPreviewPolicy.allows(mode: mode, enabled: enabled, shiftOverride: override, shiftPressed: shift, size: size, sourceURL: source)
		}
		precondition(allows("always"))
		precondition(!allows("never"))
		precondition(!allows("search"))
		precondition(allows("search", source: search))
		precondition(!allows("search", source: nil))
		precondition(!allows("always", enabled: false))
		precondition(allows("never", shift: true, override: true, enabled: false))
		precondition(!allows("never", shift: true))
		precondition(!allows("never", override: true))
		for size in [CGSize(width: 100, height: 20), CGSize(width: 20, height: 100), .zero, CGSize(width: -1, height: 20), CGSize(width: CGFloat.infinity, height: 20), CGSize(width: CGFloat.nan, height: 20)] {
			for mode in ["always", "never", "search"] {
				precondition(!allows(mode, source: search, size: size, shift: true, override: true))
			}
		}
		let custom = BrowserSearchConfiguration(customTemplate: "https://search.example.com/find?term={query}")
		precondition(BrowserLinkPreviewPolicy.allows(mode: "search", enabled: true, shiftOverride: false, shiftPressed: false, size: CGSize(width: 20, height: 20), sourceURL: URL(string: "https://search.example.com/find?term=swift"), configuration: custom))
		print("Hover preview policy checks passed")
	}
}
