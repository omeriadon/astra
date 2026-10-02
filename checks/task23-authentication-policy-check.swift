import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
	guard condition() else {
		fatalError(message)
	}
}

@main
struct AuthenticationSessionPolicyCheck {
	static func main() {
		let url = URL(string: "https://login.example.test/start")!
		let request = BrowserAuthenticationPolicy.initialRequest(
			url: url,
			headers: [
				"Authorization": "Bearer opaque-value",
				"X-Session-Context": "opaque-value",
			]
		)
		check(request?.value(forHTTPHeaderField: "X-Session-Context") == "opaque-value", "authorized custom initial headers are retained")
		check(request?.value(forHTTPHeaderField: "Authorization") == "Bearer opaque-value", "authorized credential headers remain part of the initial request")
		check(BrowserAuthenticationPolicy.initialRequest(url: url, headers: ["X-Test": "one\r\ntwo"]) == nil, "header line breaks are rejected")
		check(BrowserAuthenticationPolicy.initialRequest(url: url, headers: ["Bad Header": "value"]) == nil, "invalid header names are rejected")
		check(BrowserAuthenticationPolicy.initialRequest(url: url, headers: ["Cookie": "secret=value"]) == nil, "browser-managed cookie header is rejected")
		check(BrowserAuthenticationPolicy.initialRequest(url: url, headers: ["Set-Cookie": "secret=value"]) == nil, "response cookie headers cannot be sent as request fields")
		check(BrowserAuthenticationPolicy.initialRequest(url: url, headers: ["X-Test": "one", "x-test": "two"]) == nil, "case-insensitive duplicate fields are rejected")
		check(BrowserAuthenticationPolicy.initialRequest(url: url, headers: ["Sec-Fetch-Site": "cross-site"]) == nil, "browser security headers cannot be overridden")
		check(BrowserAuthenticationPolicy.initialRequest(url: url, headers: ["X-Test": String(repeating: "a", count: 8_193)]) == nil, "oversized header is rejected")
		check(BrowserAuthenticationPolicy.initialRequest(url: URL(string: "https://user:password@example.test")!, headers: nil) == nil, "URL user information is rejected")
		check(BrowserAuthenticationPolicy.initialRequest(url: URL(string: "file:///tmp/login")!, headers: nil) == nil, "non-web authentication URLs are rejected")

		check(BrowserAuthenticationPolicy.canInterceptCallback(isSourceMainFrame: true, targetsMainFrame: true, isNewWindow: false), "main-frame callback navigation is eligible")
		check(BrowserAuthenticationPolicy.canInterceptCallback(isSourceMainFrame: true, targetsMainFrame: false, isNewWindow: true), "main-frame callback popup is eligible")
		check(!BrowserAuthenticationPolicy.canInterceptCallback(isSourceMainFrame: false, targetsMainFrame: true, isNewWindow: false), "subframe callback cannot complete authentication")
		check(!BrowserAuthenticationPolicy.canInterceptCallback(isSourceMainFrame: false, targetsMainFrame: false, isNewWindow: true), "subframe popup cannot complete authentication")

		let firstGeneration = UUID()
		let replacementGeneration = UUID()
		check(BrowserAuthenticationPolicy.isCurrentSession(generation: firstGeneration, currentGeneration: firstGeneration, sameRequest: true, sameWindow: true), "current request and window own the callback")
		check(!BrowserAuthenticationPolicy.isCurrentSession(generation: firstGeneration, currentGeneration: replacementGeneration, sameRequest: true, sameWindow: true), "replacement invalidates callbacks from the prior generation")
		check(!BrowserAuthenticationPolicy.isCurrentSession(generation: firstGeneration, currentGeneration: nil, sameRequest: true, sameWindow: true), "cancellation or close invalidates callbacks after session removal")
		check(!BrowserAuthenticationPolicy.isCurrentSession(generation: firstGeneration, currentGeneration: firstGeneration, sameRequest: false, sameWindow: true), "request identity is part of callback ownership")
		check(!BrowserAuthenticationPolicy.isCurrentSession(generation: firstGeneration, currentGeneration: firstGeneration, sameRequest: true, sameWindow: false), "window identity is part of callback ownership")
	}
}
