import CFNetwork
import Foundation

struct BrowserNavigationFailure {
	let kind: Kind
	let url: URL

	init(kind: Kind, url: URL) {
		self.kind = kind
		self.url = url
	}

	init(error: NSError, url: URL) {
		self.url = url
		// WebKit often wraps a CFNetwork proxy error in a generic URL-loading
		// error. Examine the underlying chain before classifying that wrapper.
		if let proxyFailure = Self.proxyFailureKind(in: error) {
			kind = proxyFailure
			return
		}
		guard error.domain == NSURLErrorDomain else {
			kind = .other
			return
		}

		switch error.code {
			case NSURLErrorNotConnectedToInternet:
				kind = .offline
			case NSURLErrorNetworkConnectionLost:
				kind = .connectionLost
			case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
				kind = .websiteNotFound
			case NSURLErrorCannotConnectToHost:
				// CFNetwork sometimes reduces a refused manual proxy connection to
				// -1004. Only infer a proxy failure for an explicit system proxy
				// selected for this URL; never treat every -1004 as a proxy error.
				kind = Self.hasManualSystemProxy(for: url) ? .proxyConnectionFailed : .cannotConnect
			case NSURLErrorTimedOut:
				kind = .timedOut
			case NSURLErrorSecureConnectionFailed,
			     NSURLErrorAppTransportSecurityRequiresSecureConnection,
			     NSURLErrorServerCertificateHasBadDate,
			     NSURLErrorServerCertificateUntrusted,
			     NSURLErrorServerCertificateHasUnknownRoot,
			     NSURLErrorServerCertificateNotYetValid:
				kind = .secureConnectionFailed
			case NSURLErrorBadURL, NSURLErrorUnsupportedURL:
				kind = .invalidAddress
			case NSURLErrorHTTPTooManyRedirects:
				kind = .tooManyRedirects
			case NSURLErrorBadServerResponse,
			     NSURLErrorCannotParseResponse,
			     NSURLErrorCannotDecodeRawData,
			     NSURLErrorCannotDecodeContentData:
				kind = .invalidResponse
			default:
				kind = .other
		}
	}

	private static func proxyFailureKind(in error: NSError) -> Kind? {
		var current: NSError? = error
		var visited = Set<ObjectIdentifier>()
		// NSError chains are untrusted and can theoretically contain cycles.
		for _ in 0..<8 {
			guard let next = current,
			      visited.insert(ObjectIdentifier(next)).inserted else { break }
			if next.domain == (kCFErrorDomainCFNetwork as String) || next.domain == NSURLErrorDomain,
			   let code = Int32(exactly: next.code),
			   let networkError = CFNetworkErrors(rawValue: code)
			{
				switch networkError {
					case .cfErrorHTTPProxyConnectionFailure,
					     .cfErrorHTTPSProxyConnectionFailure,
					     .cfStreamErrorHTTPSProxyFailureUnexpectedResponseToCONNECTMethod,
					     .cfsocksErrorUnknownClientVersion,
					     .cfsocksErrorUnsupportedServerVersion,
					     .cfsocks4ErrorRequestFailed,
					     .cfsocks4ErrorIdentdFailed,
					     .cfsocks4ErrorIdConflict,
					     .cfsocks4ErrorUnknownStatusCode,
					     .cfsocks5ErrorBadState,
					     .cfsocks5ErrorBadResponseAddr,
					     .cfsocks5ErrorUnsupportedNegotiationMethod:
						return .proxyConnectionFailed
					case .cfErrorHTTPBadProxyCredentials,
					     .cfErrorPACFileAuth,
					     .cfsocks5ErrorBadCredentials,
					     .cfsocks5ErrorNoAcceptableMethod:
						return .proxyAuthenticationFailed
					case .cfErrorPACFileError:
						return .proxyConfigurationFailed
					default:
						break
				}
			}
			current = next.userInfo[NSUnderlyingErrorKey] as? NSError
		}
		return nil
	}

	private static func hasManualSystemProxy(for url: URL) -> Bool {
		guard let scheme = url.scheme?.lowercased(),
		      scheme == "http" || scheme == "https",
		      let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue()
		else { return false }

		// Respects per-destination exclusions. A PAC entry is not proof that
		// the failed request actually used a proxy, so leave it unclassified.
		let proxies = CFNetworkCopyProxiesForURL(url as CFURL, settings).takeRetainedValue()
		guard let first = (proxies as NSArray).firstObject as? [String: Any],
		      let type = first[kCFProxyTypeKey as String] as? String else { return false }
		return type == (kCFProxyTypeHTTP as String)
			|| type == (kCFProxyTypeHTTPS as String)
			|| type == (kCFProxyTypeSOCKS as String)
	}

	static func canRetryAutomatically(_ request: URLRequest?) -> Bool {
		guard let request,
		      request.httpBody == nil,
		      request.httpBodyStream == nil
		else { return false }
		return ["GET", "HEAD"].contains((request.httpMethod ?? "GET").uppercased())
	}

	enum Kind: String, Hashable, CaseIterable {
		case offline
		case connectionLost
		case websiteNotFound
		case cannotConnect
		case proxyConnectionFailed
		case proxyAuthenticationFailed
		case proxyConfigurationFailed
		case timedOut
		case secureConnectionFailed
		case invalidAddress
		case tooManyRedirects
		case invalidResponse
		case webContentTerminated
		case repeatedWebContentTermination
		case other

		var title: LocalizedStringResource {
			switch self {
				case .offline: "No Internet Connection"
				case .connectionLost: "Connection Lost"
				case .websiteNotFound: "Website Not Found"
				case .cannotConnect: "Cannot Connect to Server"
				case .proxyConnectionFailed: "Cannot Connect to Proxy"
				case .proxyAuthenticationFailed: "Proxy Authentication Failed"
				case .proxyConfigurationFailed: "Proxy Configuration Failed"
				case .timedOut: "Connection Timed Out"
				case .secureConnectionFailed: "Secure Connection Failed"
				case .invalidAddress: "Invalid Web Address"
				case .tooManyRedirects: "Too Many Redirects"
				case .invalidResponse: "Invalid Server Response"
				case .webContentTerminated: "Page Stopped Working"
				case .repeatedWebContentTermination: "Page Keeps Stopping"
				case .other: "Cannot Open Page"
			}
		}

		var description: LocalizedStringResource {
			switch self {
				case .offline: "Connect to the internet and try again."
				case .connectionLost: "The network connection was interrupted. Try again."
				case .websiteNotFound: "Check the website address and try again."
				case .cannotConnect: "The server is not responding. Try again later."
				case .proxyConnectionFailed: "Astra could not connect through the configured proxy. Check your proxy settings and try again."
				case .proxyAuthenticationFailed: "The proxy rejected the authentication credentials. Check your proxy login and try again."
				case .proxyConfigurationFailed: "The proxy auto-configuration could not be used. Check your network proxy settings."
				case .timedOut: "The server took too long to respond. Try again."
				case .secureConnectionFailed: "A secure connection to this website could not be established."
				case .invalidAddress: "Check the web address and try again."
				case .tooManyRedirects: "This website redirected too many times."
				case .invalidResponse: "The server sent a response that could not be read."
				case .webContentTerminated: "This page closed unexpectedly. Try loading it again."
				case .repeatedWebContentTermination: "This page stopped repeatedly. Close it and try again later."
				case .other: "An error occurred while opening this page. Try again."
			}
		}

		var systemImage: String {
			switch self {
				case .offline, .connectionLost: "wifi.slash"
				case .websiteNotFound: "globe"
				case .cannotConnect, .timedOut, .proxyConnectionFailed, .proxyAuthenticationFailed, .proxyConfigurationFailed: "network"
				case .secureConnectionFailed: "lock.shield"
				case .invalidAddress: "link"
				case .tooManyRedirects: "arrow.triangle.2.circlepath"
				case .invalidResponse, .webContentTerminated, .repeatedWebContentTermination, .other: "exclamationmark.triangle"
			}
		}
	}
}

struct BrowserContentProcessTerminationTracker {
	private(set) var count = 0
	private var url: URL?
	private var lastTerminationAt: Date?

	mutating func navigationCommitted(at nextURL: URL?) {
		guard let nextURL, url != nextURL else { return }
		count = 0
		url = nil
		lastTerminationAt = nil
	}

	mutating func record(_ nextURL: URL, at date: Date = .now) -> Bool {
		// ponytail: fixed 60-second repeat window; tune from observed crash recovery data.
		if url != nextURL || lastTerminationAt.map({ date.timeIntervalSince($0) > 60 }) ?? true {
			count = 0
		}
		url = nextURL
		lastTerminationAt = date
		count += 1
		return count > 1
	}
}
