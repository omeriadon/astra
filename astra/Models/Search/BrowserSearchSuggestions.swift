import Foundation

struct BrowserSearchSuggestionsRequest: Hashable {
	let query: String
	let generation: Int
	let provider: BrowserSearchConfiguration.Engine
	let isPrivate: Bool
	let configuration: String
	let suggestionsEnabled: Bool
}

enum BrowserSearchSuggestions {
	private static let session = URLSession(configuration: .ephemeral)
	private static let responseLimit = 131_072
	private static let openSearchLimit = 65_536

	static func fetch(
		for query: String,
		provider: BrowserSearchConfiguration.Engine
	) async throws -> [String] {
		guard (2 ... 500).contains(query.count),
		      provider == .google || provider == .duckDuckGo,
		      let url = suggestionURL(for: query, provider: provider)
		else {
			return []
		}
		var request = URLRequest(url: url)
		request.timeoutInterval = 3
		let (bytes, response) = try await session.bytes(for: request)
		defer { bytes.task.cancel() }
		guard let response = response as? HTTPURLResponse,
		      response.statusCode == 200
		else {
			return []
		}
		var data = Data()
		for try await byte in bytes {
			guard data.count < responseLimit else {
				throw URLError(.dataLengthExceedsMaximum)
			}
			data.append(byte)
		}
		try Task.checkCancellation()
		guard let payload = try JSONSerialization.jsonObject(with: data) as? [Any],
		      let suggestions = parsedSuggestions(payload, query: query, provider: provider)
		else {
			return []
		}
		var seen = Set<String>()
		return Array(suggestions.filter {
			!$0.isEmpty && $0.count <= 500
				&& seen.insert(BrowserSearchMatching.normalized($0)).inserted
		}.prefix(4))
	}

	static func discoverOpenSearchTemplate(for websiteURL: URL) async throws -> String? {
		guard let website = URLComponents(url: websiteURL, resolvingAgainstBaseURL: false),
		      website.scheme?.lowercased() == "https",
		      let host = website.host, !host.isEmpty,
		      website.user == nil, website.password == nil
		else { return nil }
		var endpoint = URLComponents()
		endpoint.scheme = "https"
		endpoint.host = host
		endpoint.port = website.port
		endpoint.path = "/opensearch.xml"
		guard let url = endpoint.url else { return nil }
		var request = URLRequest(url: url)
		request.timeoutInterval = 3
		let (bytes, response) = try await session.bytes(for: request)
		defer { bytes.task.cancel() }
		guard let response = response as? HTTPURLResponse,
		      response.statusCode == 200,
		      let finalURL = response.url,
		      finalURL.scheme?.lowercased() == "https",
		      finalURL.host?.lowercased() == host.lowercased()
		else { return nil }
		var data = Data()
		for try await byte in bytes {
			guard data.count < openSearchLimit else { return nil }
			data.append(byte)
		}
		try Task.checkCancellation()
		return BrowserSearchMatching.openSearchTemplate(from: data)
	}

	static func suggestionURL(for query: String, provider: BrowserSearchConfiguration.Engine) -> URL? {
		var components: URLComponents?
		switch provider {
			case .google:
				components = URLComponents(string: "https://suggestqueries.google.com/complete/search")
				components?.queryItems = [
					URLQueryItem(name: "client", value: "firefox"),
					URLQueryItem(name: "q", value: query),
				]
			case .duckDuckGo:
				components = URLComponents(string: "https://ac.duckduckgo.com/ac/")
				components?.queryItems = [URLQueryItem(name: "q", value: query)]
			case .bing, .custom:
				return nil
		}
		guard var finalComponents = components else {
			return nil
		}
		finalComponents.percentEncodedQuery = finalComponents.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
		return finalComponents.url
	}

	static func parsedSuggestions(
		_ payload: [Any],
		query: String,
		provider: BrowserSearchConfiguration.Engine
	) -> [String]? {
		switch provider {
			case .google:
				guard payload.count >= 2,
				      payload[0] as? String == query,
				      let values = payload[1] as? [String]
				else {
					return nil
				}
				return values
			case .duckDuckGo:
				return payload.compactMap { ($0 as? [String: Any])?["phrase"] as? String }
			case .bing, .custom:
				return nil
		}
	}
}
