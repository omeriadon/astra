import Foundation

@main
struct SyncServerAddressCheck {
	static func main() {
		assert(SyncServerAddress.normalized("  EXAMPLE.com:9644  ")?.absoluteString == "https://example.com:9644")
		assert(!SyncServerAddress.isBound(nil, to: nil))
		assert(!SyncServerAddress.isBound("https://example.com", to: nil))
		assert(SyncServerAddress.isBound("https://example.com", to: URL(string: "https://example.com")))
		assert(SyncServerAddress.normalized("HTTPS://203.17.177.58:9644")?.absoluteString == "https://203.17.177.58:9644")
		assert(SyncServerAddress.normalized("203.17.177.58:9644")?.absoluteString == "https://203.17.177.58:9644")
		assert(SyncServerAddress.normalized("https://[2001:db8::1]:9644") != nil)
		assert(SyncServerAddress.normalized("https://example.com/path")?.path == "/path")
		assert(SyncServerAddress.normalized("http://example.com") == nil)
		assert(SyncServerAddress.normalized("http://localhost:8080", allowLocalHTTP: true) != nil)
		assert(SyncServerAddress.normalized("http://[::1]", allowLocalHTTP: true) != nil)
		assert(SyncServerAddress.normalized("https://exa%20mple.com") == nil)
		assert(SyncServerAddress.normalized("https://user:secret@example.com") == nil)
		assert(SyncServerAddress.normalized("https://example.com:70000") == nil)
		assert(SyncServerAddress.normalized("https://example.com:bad") == nil)
		assert(SyncServerAddress.normalized("ftp://example.com") == nil)
		assert(SyncServerAddress.normalized("https://example.com?token=x") == nil)
		assert(SyncServerAddress.normalized("https://[bad-ipv6") == nil)
	}
}
