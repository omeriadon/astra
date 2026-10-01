import Foundation

enum BrowserNavigationPolicy {
	private static let engineSchemes: Set<String> = [
		"about", "blob", "chrome", "chrome-extension", "data", "devtools", "file", "http", "https",
		"javascript", "moz-extension", "resource", "safari-extension", "view-source",
		"webkit", "webkit-extension",
	]

	nonisolated static func externalApplicationScheme(for url: URL) -> String? {
		guard let scheme = url.scheme?.lowercased(),
		      !engineSchemes.contains(scheme),
		      scheme != "astra",
		      !scheme.hasPrefix("astra-")
		else { return nil }
		return scheme
	}
}
