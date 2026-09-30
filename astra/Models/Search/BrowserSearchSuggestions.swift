import Foundation

enum BrowserSearchSuggestions {
	private static let session = URLSession(configuration: .ephemeral)

	static func fetch(for query: String) async throws -> [String] {
		guard (2 ... 500).contains(query.count),
		      BrowserAddress.isGoogleSearchURL(BrowserAddress.destination(for: query))
		else { return [] }
		var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")
		components?.queryItems = [
			URLQueryItem(name: "client", value: "firefox"),
			URLQueryItem(name: "q", value: query),
		]
		guard let url = components?.url else { return [] }
		var request = URLRequest(url: url)
		request.timeoutInterval = 3
		let (data, response) = try await session.data(for: request)
		guard let response = response as? HTTPURLResponse,
		      response.statusCode == 200, data.count < 131_072,
		      let payload = try JSONSerialization.jsonObject(with: data) as? [Any],
		      payload.count >= 2, payload[0] as? String == query,
		      let suggestions = payload[1] as? [String]
		else { return [] }
		var seen = Set<String>()
		return Array(suggestions.filter {
			!$0.isEmpty && $0.count <= 500
				&& seen.insert(BrowserSearchMatching.normalized($0)).inserted
		}.prefix(4))
	}
}
