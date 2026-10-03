#if os(macOS)
import Foundation

@main
struct BrowserSourceViewerChecks {
	static func main() {
		precondition(BrowserSourceDocumentPolicy.accepts("<html></html>"))
		precondition(!BrowserSourceDocumentPolicy.accepts(""))
		precondition(BrowserSourceDocumentPolicy.accepts(String(repeating: "a", count: BrowserSourceDocumentPolicy.maximumBytes)))
		precondition(!BrowserSourceDocumentPolicy.accepts(String(repeating: "a", count: BrowserSourceDocumentPolicy.maximumBytes + 1)))
		precondition(!BrowserSourceDocumentPolicy.accepts(String(repeating: "é", count: BrowserSourceDocumentPolicy.maximumBytes / 2 + 1)))
	}
}
#endif
