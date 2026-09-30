import Foundation

@main
struct WatchLinkChecks {
	static func main() {
		for url in ["https://example.com/page?q=1", "http://example.com", "HTTPS://example.com"] {
			assert(WatchLink(id: UUID(), title: "", url: URL(string: url)!).canOpen)
		}
		for url in ["file:///private/data", "javascript:alert(1)", "astra://bookmarks", "https:relative", "about:blank"] {
			assert(!WatchLink(id: UUID(), title: "", url: URL(string: url)!).canOpen)
		}
		print("Watch link validation checks passed")
	}
}
