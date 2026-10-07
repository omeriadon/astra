import Foundation
import WebKit

struct BrowserSearchSuggestionsRequest: Hashable {
	let query: String
	let generation: Int
	let scope: String
	let provider: BrowserSearchConfiguration.Engine
	let isPrivate: Bool
	let configuration: String
	let suggestionsEnabled: Bool
}

enum BrowserSearchSuggestions {
	private static let session = URLSession(configuration: .ephemeral)
	private static let responseLimit = 131_072
	private static let openSearchLimit = 65536

	static func fetch(
		for query: String,
		provider: BrowserSearchConfiguration.Engine
	) async throws -> [String] {
		BrowserLog.debug(.search, "suggestions.fetch", metadata: ["query": BrowserLog.value(query), "provider": String(describing: provider)])
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

	@MainActor
	static func discoverOpenSearchTemplate(in webView: WKWebView) async throws -> BrowserSearchEngineDiscoveryOutcome {
		BrowserLog.debug(.search, "opensearch.discover", metadata: ["page": BrowserLog.url(webView.url)])
		guard let pageURL = webView.url,
		      let page = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
		      page.scheme?.lowercased() == "https",
		      page.user == nil, page.password == nil
		else { return .blocked }
		let script = """
		(() => {
		  const links = Array.from(document.querySelectorAll('link[rel~="search"]'));
		  const link = links.find(value =>
		    (value.type || '').toLowerCase().split(';')[0].trim() === 'application/opensearchdescription+xml'
		  );
		  return link ? link.href : null;
		})()
		"""
		let scriptResult = try await webView.evaluateJavaScript(script)
		guard !Task.isCancelled else { return .cancelled }
		guard let href = scriptResult as? String else { return .notPublished }
		guard href.utf8.count <= 2048,
		      let metadataURL = URL(string: href, relativeTo: pageURL)?.absoluteURL,
		      let metadata = URLComponents(url: metadataURL, resolvingAgainstBaseURL: false),
		      metadata.scheme?.lowercased() == "https",
		      metadata.user == nil, metadata.password == nil,
		      webView.url == pageURL
		else { return .blocked }
		var request = URLRequest(url: metadataURL)
		request.timeoutInterval = 3
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpCookieStorage = nil
		configuration.httpShouldSetCookies = false
		configuration.urlCredentialStorage = nil
		let redirectPolicy = OpenSearchRedirectPolicy()
		let metadataSession = URLSession(configuration: configuration, delegate: redirectPolicy, delegateQueue: nil)
		defer { metadataSession.invalidateAndCancel() }
		let (bytes, response) = try await metadataSession.bytes(for: request)
		defer { bytes.task.cancel() }
		guard let response = response as? HTTPURLResponse else { return .failed }
		guard response.statusCode == 200 else {
			return (300 ... 399).contains(response.statusCode) ? .blocked : .failed
		}
		guard let finalURL = response.url,
		      finalURL.scheme?.lowercased() == "https",
		      let final = URLComponents(url: finalURL, resolvingAgainstBaseURL: false),
		      final.user == nil, final.password == nil,
		      webView.url == pageURL
		else { return .blocked }
		var data = Data()
		for try await byte in bytes {
			guard data.count < openSearchLimit else { return .invalid }
			data.append(byte)
		}
		try Task.checkCancellation()
		guard webView.url == pageURL else { return .cancelled }
		guard let template = BrowserSearchMatching.openSearchTemplate(from: data) else { return .invalid }
		return .found(template)
	}

	static func suggestionURL(for query: String, provider: BrowserSearchConfiguration.Engine) -> URL? {
		BrowserLog.trace(.search, "suggestions.url", metadata: ["query": BrowserLog.value(query), "provider": String(describing: provider)])
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

private final class OpenSearchRedirectPolicy: NSObject, URLSessionTaskDelegate {
	func urlSession(
		_: URLSession,
		task _: URLSessionTask,
		willPerformHTTPRedirection _: HTTPURLResponse,
		newRequest request: URLRequest,
		completionHandler: @escaping (URLRequest?) -> Void
	) {
		guard let url = request.url,
		      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      components.scheme?.lowercased() == "https",
		      components.user == nil, components.password == nil
		else {
			completionHandler(nil)
			return
		}
		completionHandler(request)
	}
}
