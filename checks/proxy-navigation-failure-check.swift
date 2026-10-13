import CFNetwork
import Foundation

@main
struct ProxyNavigationFailureCheck {
	static func main() {
		let url = URL(string: "https://example.com/")!
		let cfNetwork = kCFErrorDomainCFNetwork as String

		for (code, kind) in [
			(306, BrowserNavigationFailure.Kind.proxyUnavailable),
			(310, .proxyUnavailable),
			(307, .proxyAuthenticationRequired),
			(309, .proxyAuthenticationRequired),
			(122, .proxyAuthenticationRequired),
			(308, .proxyConfigurationFailed),
			(311, .proxyRejectedConnection),
			(110, .proxyRejectedConnection),
			(124, .proxyRejectedConnection),
		] {
			let error = NSError(domain: cfNetwork, code: code)
			let result = BrowserNavigationFailure(error: error, url: url)
			precondition(result.kind == kind, "Proxy error \(code) should be \(kind)")
			precondition(result.isProxyFailure)
		}

		let nestedProxy = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost, userInfo: [
			NSUnderlyingErrorKey: NSError(domain: cfNetwork, code: 310),
		])
		precondition(BrowserNavigationFailure(error: nestedProxy, url: url).kind == .proxyUnavailable)

		// A normal server failure must not be blamed on a configured proxy.
		for (code, expected) in [
			(NSURLErrorCannotConnectToHost, BrowserNavigationFailure.Kind.cannotConnect),
			(NSURLErrorTimedOut, .timedOut),
			(NSURLErrorCannotFindHost, .websiteNotFound),
			(NSURLErrorNotConnectedToInternet, .offline),
		] {
			let result = BrowserNavigationFailure(error: NSError(domain: NSURLErrorDomain, code: code), url: url)
			precondition(result.kind == expected)
			precondition(!result.isProxyFailure)
		}

		let authRequired = NSError(domain: NSURLErrorDomain, code: NSURLErrorUserAuthenticationRequired)
		precondition(BrowserNavigationFailure(error: authRequired, url: url).kind == .other)
		precondition(BrowserNavigationFailure(
			error: authRequired, url: url, encounteredProxyAuthentication: true
		).kind == .proxyAuthenticationRequired)
		let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorUserCancelledAuthentication)
		precondition(!BrowserNavigationFailure(
			error: cancelled, url: url, encounteredProxyAuthentication: true
		).isProxyFailure)

		// Identical numeric codes from unrelated NSError domains are not CFNetwork proxy failures.
		precondition(BrowserNavigationFailure(
			error: NSError(domain: NSPOSIXErrorDomain, code: 306), url: url
		).kind == .other)
		print("Proxy navigation failure classification checks passed")
	}
}
