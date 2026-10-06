import Foundation

@MainActor
enum BrowserReaderScript {
	static let source: String? = {
		let bundle = Bundle(for: BrowserController.self)
		var scripts: [String] = []
		for name in ["Readability", "Readability-readerable", "Reader"] {
			guard let url = bundle.url(forResource: name, withExtension: "js"),
			      let script = try? String(contentsOf: url, encoding: .utf8)
			else { return nil }
			scripts.append(script)
		}
		return scripts.joined(separator: "\n")
	}()

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
		@media (prefers-color-scheme: dark) { body { color: #e7e5df; background: #20211f; } a { color: #8bbcf5; } }
		</style></head><body><main><h1>\(escape(article["title"] ?? ""))</h1>
		<p class="byline">\(escape(article["byline"] ?? ""))</p>\(article["content"] ?? "")</main></body></html>
		"""
	}
}
