import Foundation

@main
enum NavigationPolicyCheck {
	static func main() {
		for scheme in ["mailto", "tel", "sms", "facetime", "maps", "music", "itms-apps", "system-preferences", "custom-app"] {
			assert(BrowserNavigationPolicy.externalApplicationScheme(for: URL(string: "\(scheme):payload")!) == scheme)
		}
		for scheme in ["http", "https", "about", "file", "javascript", "data", "blob", "webkit-extension", "astra", "astra-settings"] {
			assert(BrowserNavigationPolicy.externalApplicationScheme(for: URL(string: "\(scheme):payload")!) == nil)
		}
		assert(BrowserAddress.destination(for: "mailto:person@example.com")?.scheme == "mailto")
		assert(BrowserAddress.destination(for: "custom-app:open")?.absoluteString == "custom-app:open")
		assert(BrowserAddress.destination(for: "com.example.app://open")?.scheme == "com.example.app")
		assert(BrowserAddress.destination(for: "javascript:alert(1)") == nil)
		assert(BrowserAddress.destination(for: "example.com")?.absoluteString == "https://example.com")
		assert(BrowserAddress.destination(for: "localhost")?.absoluteString == "https://localhost")
		assert(BrowserAddress.destination(for: "localhost:8765")?.absoluteString == "https://localhost:8765")
		assert(BrowserAddress.destination(for: "localhost:8765/path")?.absoluteString == "https://localhost:8765/path")
		assert(BrowserAddress.destination(for: "example.com:8443/path")?.absoluteString == "https://example.com:8443/path")
		assert(BrowserAddress.destination(for: "example.com:bad/path")?.host == "www.google.com")
		assert(BrowserAddress.destination(for: "localhost:bad/path")?.host == "www.google.com")
		assert(BrowserAddress.destination(for: "example.com:70000")?.host == "www.google.com")
		assert(BrowserAddress.destination(for: "https://example.com:70000") == nil)
	}
}
