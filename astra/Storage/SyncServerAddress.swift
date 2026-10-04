import Foundation

nonisolated enum SyncServerAddress {
	static func isBound(_ endpoint: String?, to currentAddress: URL?) -> Bool {
		guard let endpoint, let currentAddress else { return false }
		return endpoint == currentAddress.absoluteString
	}

	static func normalized(_ input: String, allowLocalHTTP: Bool = false) -> URL? {
		let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }
		let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
		guard var components = URLComponents(string: candidate),
		      let scheme = components.scheme?.lowercased(),
		      let host = components.host, !host.isEmpty,
		      !host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
		      components.user == nil, components.password == nil,
		      components.query == nil, components.fragment == nil,
		      components.port.map({ (1 ... 65535).contains($0) }) ?? true
		else { return nil }
		guard scheme == "https" || (allowLocalHTTP && scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())) else {
			return nil
		}
		components.scheme = scheme
		components.host = host.lowercased()
		if components.path == "/" {
			components.path = ""
		}
		return components.url
	}
}
