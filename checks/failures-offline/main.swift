import CFNetwork
import Foundation

let url = URL(string: "https://example.invalid")!
let get = URLRequest(url: url)
var head = URLRequest(url: url)
head.httpMethod = "HEAD"
var post = URLRequest(url: url)
post.httpMethod = "POST"
post.httpBody = Data("field=value".utf8)
var emptyPost = URLRequest(url: url)
emptyPost.httpMethod = "POST"

assert(BrowserNavigationFailure.canRetryAutomatically(get))
assert(BrowserNavigationFailure.canRetryAutomatically(head))
assert(!BrowserNavigationFailure.canRetryAutomatically(post))
assert(!BrowserNavigationFailure.canRetryAutomatically(emptyPost))
assert(!BrowserNavigationFailure.canRetryAutomatically(nil))
assert(BrowserNavigationFailure(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorDNSLookupFailed), url: url).kind == .websiteNotFound)
assert(BrowserNavigationFailure(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost), url: url).kind == .connectionLost)
assert(BrowserNavigationFailure(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed), url: url).kind == .secureConnectionFailed)
assert(BrowserNavigationFailure(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorHTTPTooManyRedirects), url: url).kind == .tooManyRedirects)
assert(BrowserNavigationFailure(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL), url: url).kind == .invalidAddress)


func checkProxyFailure(_ error: CFNetworkErrors, expected: BrowserNavigationFailure.Kind) {
	let networkError = NSError(
		domain: kCFErrorDomainCFNetwork as String,
		code: Int(error.rawValue)
	)
	assert(BrowserNavigationFailure(error: networkError, url: url).kind == expected)
	// WKWebView often reports -1004 with the meaningful CFNetwork code below it.
	let wrapped = NSError(
		domain: NSURLErrorDomain,
		code: NSURLErrorCannotConnectToHost,
		userInfo: [NSUnderlyingErrorKey: networkError]
	)
	assert(BrowserNavigationFailure(error: wrapped, url: url).kind == expected)
}

for code: CFNetworkErrors in [
	.cfErrorHTTPProxyConnectionFailure,
	.cfErrorHTTPSProxyConnectionFailure,
	.cfStreamErrorHTTPSProxyFailureUnexpectedResponseToCONNECTMethod,
	.cfsocks4ErrorRequestFailed,
	.cfsocks5ErrorBadResponseAddr,
	.cfsocks5ErrorUnsupportedNegotiationMethod,
] {
	checkProxyFailure(code, expected: .proxyConnectionFailed)
}
for code: CFNetworkErrors in [
	.cfErrorHTTPBadProxyCredentials,
	.cfErrorPACFileAuth,
	.cfsocks5ErrorBadCredentials,
	.cfsocks5ErrorNoAcceptableMethod,
] {
	checkProxyFailure(code, expected: .proxyAuthenticationFailed)
}
checkProxyFailure(.cfErrorPACFileError, expected: .proxyConfigurationFailed)
assert(BrowserNavigationFailure(error: NSError(
	domain: NSURLErrorDomain,
	code: NSURLErrorTimedOut,
	userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 61)]
), url: url).kind == .timedOut)
assert(BrowserNavigationFailure(error: NSError(
	domain: kCFErrorDomainCFNetwork as String,
	code: Int(CFNetworkErrors.cfErrorHTTPConnectionLost.rawValue)
), url: url).kind == .other)

var terminations = BrowserContentProcessTerminationTracker()
let firstTermination = Date(timeIntervalSince1970: 1000)
assert(!terminations.record(url, at: firstTermination))
terminations.navigationCommitted(at: url)
assert(terminations.record(url, at: firstTermination.addingTimeInterval(1)))
let otherURL = URL(string: "https://other.invalid")!
terminations.navigationCommitted(at: otherURL)
assert(!terminations.record(otherURL, at: firstTermination.addingTimeInterval(2)))
assert(!terminations.record(url, at: firstTermination.addingTimeInterval(63)))
