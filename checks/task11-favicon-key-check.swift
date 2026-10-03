import Foundation

@main
enum FaviconKeyCheck {
	static func main() {
		assert(FaviconKey.origin(for: URL(string: "https://EXAMPLE.com/page")) == "https://example.com")
		assert(FaviconKey.origin(for: URL(string: "https://example.com:443/icon")) == "https://example.com")
		assert(FaviconKey.origin(for: URL(string: "http://example.com:8080/")) == "http://example.com:8080")
		assert(FaviconKey.origin(for: URL(string: "https://example.com:444/")) == "https://example.com:444")
		assert(FaviconKey.origin(for: URL(string: "file:///favicon.ico")) == nil)
		assert(FaviconKey.origin(for: nil) == nil)
	}
}
