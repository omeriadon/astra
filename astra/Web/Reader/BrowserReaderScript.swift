import Defaults
import Foundation

@MainActor
enum BrowserReaderScript {
	// WKUserScript must be installed synchronously during WebView construction.
	// Start loading bundled scripts on a utility task during root view startup,
	// but preserve the synchronous fallback if a WebView is created immediately.
	private static var prepared = false
	private static var prewarming = false
	private static var cachedSource: String?

	static var source: String? {
		if !prepared {
			cachedSource = readSource(resourceURLs())
			prepared = true
		}
		return cachedSource
	}

	static func prewarm() {
		guard !prepared, !prewarming else { return }
		prewarming = true
		let urls = resourceURLs()
		Task.detached(priority: .utility) {
			let source = readSource(urls)
			await MainActor.run {
				if !prepared {
					cachedSource = source
					prepared = true
				}
				prewarming = false
			}
		}
	}

	private static func resourceURLs() -> [URL] {
		let bundle = BrowserResources.bundle
		return ["Readability", "Readability-readerable", "Reader"].compactMap {
			bundle.url(forResource: $0, withExtension: "js")
		}
	}

	private nonisolated static func readSource(_ urls: [URL]) -> String? {
		guard urls.count == 3 else { return nil }
		var scripts: [String] = []
		scripts.reserveCapacity(urls.count)
		for url in urls {
			// Memory-map larger Readability scripts where the platform permits.
			guard let bytes = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
			scripts.append(String(decoding: bytes, as: UTF8.self))
		}
		return scripts.joined(separator: "\n")
	}

	static func document(article: [String: String]) -> String {
		func escape(_ text: String) -> String {
			text.replacingOccurrences(of: "&", with: "&amp;")
				.replacingOccurrences(of: "<", with: "&lt;")
				.replacingOccurrences(of: ">", with: "&gt;")
				.replacingOccurrences(of: "\"", with: "&quot;")
		}
		return """
		<!doctype html><html dir="\(article["dir"] == "rtl" ? "rtl" : "ltr")"><head>
		<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
		<meta name="referrer" content="no-referrer">
		<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: http:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
		<title>\(escape(article["title"] ?? ""))</title>
		<style>
		:root { color-scheme: light dark; font: -apple-system-body; }
		body { margin: 0; padding: 32px 24px 80px; color: #282724; background: #faf9f6; }
		main { max-width: 680px; margin: auto; font: 1.2em/1.7 Georgia, serif; overflow-wrap: anywhere; }
		h1 { font-size: 2em; line-height: 1.2; } h2, h3, h4 { line-height: 1.3; }
		.byline { font: 0.85em/1.5 -apple-system, sans-serif; opacity: 0.7; }
		img { max-width: 100%; height: auto; } figure { margin: 1.5em 0; }
		figcaption { font-size: 0.85em; opacity: 0.7; } a { color: #2868b2; }
		pre { overflow-x: auto; padding: 1em; background: #8881; } table { display: block; overflow-x: auto; }
		blockquote { margin-inline: 0; padding-inline-start: 1em; border-inline-start: 3px solid #8888; }
		</style><style id="reader-appearance">\(Defaults[.readerAppearance].styleSheet)</style></head><body><main><h1>\(escape(article["title"] ?? ""))</h1>
		<p class="byline">\(escape(article["byline"] ?? ""))</p>\(article["content"] ?? "")</main></body></html>
		"""
	}
}
