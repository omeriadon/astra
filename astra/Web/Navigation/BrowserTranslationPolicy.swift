import Foundation

enum BrowserTranslationPolicy {
	static let languages = ["en", "ar", "de", "es", "fr", "hi", "id", "it", "ja", "ko", "pt", "ru", "vi", "zh-CN", "zh-TW"]

	static func translationURL(for pageURL: URL, language: String, isPrivate: Bool) -> URL? {
		guard !isPrivate,
		      languages.contains(language),
		      var page = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
		      page.scheme == "https" || page.scheme == "http",
		      page.user == nil, page.password == nil,
		      let host = page.host?.lowercased(),
		      host.contains("."),
		      !host.contains(":"),
		      !host.allSatisfy({ $0.isNumber || $0 == "." }),
		      !["localhost", "local", "internal", "test", "invalid"].contains(where: { host == $0 || host.hasSuffix("." + $0) }),
		      page.port == nil || page.port == 80 || page.port == 443
		else { return nil }
		page.fragment = nil
		guard let pageURL = page.url else { return nil }
		var translation = URLComponents(string: "https://translate.google.com/translate")!
		translation.queryItems = [
			URLQueryItem(name: "sl", value: "auto"),
			URLQueryItem(name: "tl", value: language),
			URLQueryItem(name: "u", value: pageURL.absoluteString),
		]
		translation.percentEncodedQuery = translation.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
		return translation.url
	}
}
