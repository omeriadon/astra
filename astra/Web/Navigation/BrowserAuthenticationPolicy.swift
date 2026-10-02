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

	static func initialRequest(
		url: URL,
		headers: [String: String]?
	) -> URLRequest? {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
			  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
			  let host = components.host,
			  !host.isEmpty,
			  components.user == nil,
			  components.password == nil
		else { return nil }

		var request = URLRequest(url: url)
		var totalHeaderBytes = 0
		var headerNames: Set<String> = []
		for (name, value) in headers ?? [:] {
			let normalizedName = name.lowercased()
			guard isSafeHeader(name: name, value: value),
			      headerNames.insert(normalizedName).inserted else { return nil }
			totalHeaderBytes += name.utf8.count + value.utf8.count
			guard totalHeaderBytes <= 65_536 else { return nil }
			request.setValue(value, forHTTPHeaderField: name)
		}
		return request
	}

	static func canInterceptCallback(
		isSourceMainFrame: Bool,
		targetsMainFrame: Bool,
		isNewWindow: Bool
	) -> Bool {
		isSourceMainFrame && (targetsMainFrame || isNewWindow)
	}

	static func isCurrentSession(
		generation: UUID,
		currentGeneration: UUID?,
		sameRequest: Bool,
		sameWindow: Bool
	) -> Bool {
		currentGeneration == generation && sameRequest && sameWindow
	}

	private static func isSafeHeader(name: String, value: String) -> Bool {
		guard !name.isEmpty,
			  name.utf8.count <= 256,
			  value.utf8.count <= 8_192,
			  name.utf8.allSatisfy(isTokenByte),
			  value.unicodeScalars.allSatisfy({ $0.value == 9 || (32...255).contains($0.value) })
		else { return false }

		let normalizedName = name.lowercased()
		let browserManagedHeaders: Set<String> = [
			"connection",
			"content-length",
			"cookie",
			"host",
			"origin",
			"proxy-authorization",
			"referer",
			"transfer-encoding",
			"user-agent",
		]
		return !browserManagedHeaders.contains(normalizedName)
			&& !normalizedName.hasPrefix("proxy-")
			&& !normalizedName.hasPrefix("sec-")
	}

	private static func isTokenByte(_ byte: UInt8) -> Bool {
		(65...90).contains(byte)
			|| (97...122).contains(byte)
			|| (48...57).contains(byte)
			|| "!#$%&'*+-.^_`|~".utf8.contains(byte)
	}
}
