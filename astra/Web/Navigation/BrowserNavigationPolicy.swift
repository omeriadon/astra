import Foundation

nonisolated enum BrowserNavigationPolicy {
	private static let restrictedExternalHandoffSchemes: Set<String> = [
		"about", "blob", "chrome", "chrome-extension", "data", "devtools", "file", "http", "https",
		"javascript", "moz-extension", "resource", "safari-extension", "view-source",
		"webkit", "webkit-extension",
	]

	nonisolated static func externalApplicationScheme(for url: URL) -> String? {
		guard let scheme = url.scheme?.lowercased(),
		      !restrictedExternalHandoffSchemes.contains(scheme),
		      scheme != "astra",
		      !scheme.hasPrefix("astra-")
		else { return nil }
		return scheme
	}
}
