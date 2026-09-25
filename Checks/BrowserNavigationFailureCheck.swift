import Foundation

// Run: swiftc browser/Web/BrowserNavigationFailure.swift Checks/BrowserNavigationFailureCheck.swift -o /tmp/browser-navigation-failure-check && /tmp/browser-navigation-failure-check
@main
struct BrowserNavigationFailureCheck {
	static func main() {
		let url = URL(string: "https://example.com")!
		let cases: [(Int, BrowserNavigationFailure.Kind)] = [
			(NSURLErrorNotConnectedToInternet, .offline),
			(NSURLErrorCannotFindHost, .websiteNotFound),
			(NSURLErrorTimedOut, .timedOut),
			(NSURLErrorServerCertificateUntrusted, .secureConnectionFailed),
			(NSURLErrorHTTPTooManyRedirects, .tooManyRedirects),
		]

		for (code, expected) in cases {
			let error = NSError(domain: NSURLErrorDomain, code: code)
			assert(BrowserNavigationFailure(error: error, url: url).kind == expected)
		}

		let other = NSError(domain: "Example", code: NSURLErrorNotConnectedToInternet)
		assert(BrowserNavigationFailure(error: other, url: url).kind == .other)
		print("PASS: navigation error categories")
	}
}
