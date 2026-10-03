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
				kind = .cannotConnect
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
				case .cannotConnect, .timedOut: "network"
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
