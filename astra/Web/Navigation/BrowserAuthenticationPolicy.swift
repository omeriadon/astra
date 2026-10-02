import Foundation

enum BrowserAuthenticationPolicy {
	static let maximumFailures = 3
	static let credentialMethods = [
		NSURLAuthenticationMethodHTTPBasic,
		NSURLAuthenticationMethodHTTPDigest,
		NSURLAuthenticationMethodDefault,
	]

	enum Decision: Equatable {
		case prompt
		case useDefaultHandling
		case cancel
	}

	static func decision(method: String, previousFailureCount: Int) -> Decision {
		guard credentialMethods.contains(method) else { return .useDefaultHandling }
		return previousFailureCount < maximumFailures ? .prompt : .cancel
	}

	static func title(host: String, port: Int, realm: String?) -> String {
		let host = port > 0 ? "\(host):\(port)" : host
		if let realm, !realm.isEmpty {
			return "Sign in to \(host) (\(realm))"
		}
		return "Sign in to \(host)"
	}

	static func isEncrypted(protocolName: String?) -> Bool {
		protocolName?.lowercased() == "https"
	}
}
