#if os(macOS)
import Foundation

@main
struct WebsiteAppChecks {
	static func main() {
		let id = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!
		precondition(BrowserWebsiteAppPolicy.bundleIdentifier(for: id) == "dev.omeriadon.astra.website.123456781234123412341234567890ab")
		precondition(BrowserWebsiteAppPolicy.validatedName(" Astra ") == "Astra")
		precondition(BrowserWebsiteAppPolicy.validatedName("../Astra") == nil)
		precondition(BrowserWebsiteAppPolicy.validatedName("Astra/Browser") == nil)
		precondition(BrowserWebsiteAppPolicy.validatedName(String(repeating: "a", count: 161)) == nil)

		let launch = URL(string: "https://example.com/app")!
		precondition(BrowserWebsiteAppPolicy.validatedURL(launch) == launch)
		precondition(BrowserWebsiteAppPolicy.validatedURL(URL(string: "http://localhost:8080")!) != nil)
		precondition(BrowserWebsiteAppPolicy.validatedURL(URL(string: "file:///tmp/page")!) == nil)
		precondition(BrowserWebsiteAppPolicy.validatedURL(URL(string: "https://user:pass@example.com")!) == nil)
		precondition(BrowserWebsiteAppPolicy.validatedURL(URL(string: "javascript:alert(1)")!) == nil)

		precondition(BrowserWebsiteAppPolicy.shouldStayInWebsiteApp(URL(string: "https://example.com/other")!, launchURL: launch))
		precondition(BrowserWebsiteAppPolicy.shouldStayInWebsiteApp(URL(string: "https://www.example.com/other")!, launchURL: launch))
		precondition(BrowserWebsiteAppPolicy.shouldStayInWebsiteApp(URL(string: "https://account.example.com/login")!, launchURL: launch))
		precondition(!BrowserWebsiteAppPolicy.shouldStayInWebsiteApp(URL(string: "https://example.org/")!, launchURL: launch))
		precondition(!BrowserWebsiteAppPolicy.shouldStayInWebsiteApp(URL(string: "file:///tmp/page")!, launchURL: launch))

		let filename = BrowserWebsiteAppPolicy.bundleFilename(name: "A/B:C", id: id)
		precondition(filename.hasSuffix("-12345678.app"))
		precondition(!filename.contains("/"))
		precondition(!filename.contains(":"))
		print("website app checks passed")
	}
}
#endif
