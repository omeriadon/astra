import Foundation

@main
struct TranslationPolicyCheck {
	static func main() {
		let original = URL(string: "https://example.com/article?q=a+b&lang=fr#section")!
		let translated = BrowserTranslationPolicy.translationURL(for: original, language: "en", isPrivate: false)!
		let components = URLComponents(url: translated, resolvingAgainstBaseURL: false)!
		precondition(components.host == "translate.google.com")
		precondition(components.queryItems?.first(where: { $0.name == "sl" })?.value == "auto")
		precondition(components.queryItems?.first(where: { $0.name == "tl" })?.value == "en")
		precondition(components.queryItems?.first(where: { $0.name == "u" })?.value == "https://example.com/article?q=a+b&lang=fr")
		precondition(components.percentEncodedQuery?.contains("%2B") == true)
		precondition(BrowserTranslationPolicy.translationURL(for: original, language: "en", isPrivate: true) == nil)
		precondition(BrowserTranslationPolicy.translationURL(for: original, language: "invalid", isPrivate: false) == nil)
		for address in ["file:///tmp/page.html", "astra://settings", "https://user:secret@example.com", "http://localhost", "http://router", "http://printer.local", "http://127.0.0.1", "http://192.168.1.1", "http://[::1]", "https://example.com:8443"] {
			precondition(BrowserTranslationPolicy.translationURL(for: URL(string: address)!, language: "en", isPrivate: false) == nil)
		}
		print("Translation policy checks passed")
	}
}
