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
		assert(BrowserAddress.destination(for: "mailto:hello@example.com")?.scheme == "mailto")
		assert(BrowserAddress.destination(for: "javascript:alert(1)")?.host == "www.google.com")
	}
}
