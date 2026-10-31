import Foundation

enum FaviconKey {
	nonisolated static func origin(for url: URL?) -> String? {
		guard let url,
		      let scheme = url.scheme?.lowercased(),
		      scheme == "http" || scheme == "https",
		      let host = url.host?.lowercased()
		else { return nil }

		if let port = url.port, port != (scheme == "https" ? 443 : 80) {
			return "\(scheme)://\(host):\(port)"
		}
		return "\(scheme)://\(host)"
	}
}
