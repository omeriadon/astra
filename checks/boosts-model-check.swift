import Foundation

@main
enum BoostModelChecks {
	static func main() {
		precondition(BrowserBoost.normalizedDomain("https://EXAMPLE.com/path?q=1") == "example.com")
		precondition(BrowserBoost.normalizedDomain("docs.Example.COM") == "docs.example.com")
		precondition(BrowserBoost.normalizedDomain("*.example.com") == nil)
		precondition(BrowserBoost.normalizedDomain("example..com") == nil)
		precondition(BrowserBoost.normalizedDomain("https://") == nil)

		var boost = BrowserBoost(name: "Site theme", domain: "example.com")
		boost.css = "body { color: red; }"
		boost.javascript = "document.title = 'Test';"
		precondition(boost.isValidForSync)
		precondition(boost.codeByteCount > boost.css.utf8.count)

		boost.domain = "not a domain"
		precondition(!boost.isValidForSync)
		boost.domain = "example.com"

		boost.javascript = String(repeating: "x", count: 131_073)
		precondition(!boost.isValidForSync)
		boost.javascript = ""
		boost.modifiedAt = .distantPast
		precondition(!boost.isValidForSync)

		precondition(BrowserBoost.maximumCollectionCodeBytes <= 1_000_000)
		print("Boost model: normalization, validation and size limits passed")
	}
}
