import Foundation
import FoundationModels
import WebKit

nonisolated struct BrowserAIPageText: Codable, Identifiable, Sendable {
	let title: String
	let url: URL
	let text: String

	var id: String {
		url.absoluteString
	}

	var prompt: String {
		"Page title: \(title)\nURL: \(BrowserAddress.withoutCredentials(url).absoluteString)\n<page-text>\n\(text)\n</page-text>"
	}

	@MainActor static func extract(from controller: BrowserController) async throws -> Self {
		let document = controller.navigationIdentifier
		guard let webView = controller.webViewIfLoaded, !webView.isLoading else { throw BrowserAIError.pageUnavailable }
		let page = try await extract(from: webView)
		guard !Task.isCancelled, controller.navigationIdentifier == document else { throw BrowserAIError.pageUnavailable }
		return page
	}

	@MainActor static func extract(from webView: WKWebView) async throws -> Self {
		let result = try await webView.callAsyncJavaScript(extractionScript, arguments: [:], in: nil, contentWorld: .defaultClient)
		guard let value = result as? [String: String], let text = value["text"],
		      !text.isEmpty, let url = value["url"].flatMap(URL.init(string:)) else { throw BrowserAIError.pageUnavailable }
		return Self(title: value["title"] ?? url.host ?? "Page", url: url, text: text)
	}

	@MainActor func limited(to budget: Int, onlyAbove threshold: Int? = nil) async throws -> Self {
		let model = SystemLanguageModel.default
		let count = try await model.tokenCount(for: text)
		guard count > (threshold ?? budget) else { return self }
		var lower = 0
		var upper = text.count
		while lower < upper {
			try Task.checkCancellation()
			let middle = (lower + upper + 1) / 2
			let prefix = String(text.prefix(middle))
			if try await model.tokenCount(for: prefix) <= budget {
				lower = middle
			} else {
				upper = middle - 1
			}
		}
		return Self(title: title, url: url, text: String(text.prefix(lower)))
	}

	var previewContext: Self {
		// ponytail: remote previews use a 26,000-character excerpt; use a provider tokenizer if exact budgets become necessary.
		Self(title: title, url: url, text: String(text.prefix(26000)))
	}

	/// Read rendered text, including open shadow roots and same-origin frames. Never serialize HTML or form values.
	static let extractionScript = #"""
	const lines = [];
	const visited = new WeakSet();
	const blocks = /^(P|DIV|SECTION|ARTICLE|MAIN|ASIDE|HEADER|FOOTER|NAV|H[1-6]|LI|UL|OL|TABLE|TR|BLOCKQUOTE|PRE|BR|HR)$/;
	const excluded = /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE|SVG|CANVAS|INPUT|TEXTAREA|SELECT)$/;
	function walk(node, depth = 0) {
	    if (!node || depth > 200 || visited.has(node)) return;
	    visited.add(node);
	    if (node.nodeType === 3) {
	        const text = node.nodeValue.replace(/\s+/g, ' ').trim();
	        if (text) lines.push(text);
	        return;
	    }
	    if (node.nodeType === 1) {
	        if (excluded.test(node.tagName) || node.hidden || node.getAttribute('aria-hidden') === 'true'
	            || node.isContentEditable || node.closest('[contenteditable="true"]')) return;
	        const style = node.ownerDocument.defaultView.getComputedStyle(node);
	        if (style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse'
	            || style.contentVisibility === 'hidden' || style.opacity === '0') return;
	        if (blocks.test(node.tagName)) lines.push('\n');
	        if (node.tagName === 'IFRAME') {
	            try { walk(node.contentDocument?.body, depth + 1); } catch {}
	        }
	        if (node.shadowRoot) walk(node.shadowRoot, depth + 1);
	    }
	    for (const child of node.childNodes) walk(child, depth + 1);
	    if (node.nodeType === 1 && blocks.test(node.tagName)) lines.push('\n');
	}
	walk(document.body);
	const text = lines.join(' ').split('\n').map(line => line.replace(/\s+/g, ' ').trim()).filter(Boolean).join('\n');
	return { title: document.title.trim(), url: location.href, text };
	"""#
}

/// Loads a preview in an isolated, nonpersistent store without touching the user's tab or history.
@MainActor
final class BrowserAIPageLoader: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
	private let webView: WKWebView
	private var completion: CheckedContinuation<Void, Error>?
	private var earlyPage: BrowserAIPageText?
	private var earlyExtraction: Task<Void, Never>?

	override init() {
		let configuration = WKWebViewConfiguration()
		configuration.websiteDataStore = .nonPersistent()
		webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
		super.init()
		webView.navigationDelegate = self
	}

	func page(at url: URL, forPreview: Bool = false) async throws -> BrowserAIPageText {
		guard Self.allowed(url) else { throw BrowserAIError.pageUnavailable }
		return try await withTaskCancellationHandler {
			try Task.checkCancellation()
			earlyPage = nil
			if forPreview {
				let content = webView.configuration.userContentController
				content.add(self, contentWorld: .defaultClient, name: "aiPreviewPageReady")
				content.addUserScript(WKUserScript(
					source: Self.previewReadinessScript,
					injectionTime: .atDocumentEnd,
					forMainFrameOnly: true,
					in: .defaultClient
				))
			}
			defer {
				earlyExtraction?.cancel()
				earlyExtraction = nil
				webView.stopLoading()
				webView.configuration.userContentController.removeScriptMessageHandler(forName: "aiPreviewPageReady", contentWorld: .defaultClient)
				webView.configuration.userContentController.removeAllUserScripts()
			}
			let timeout = Task { [weak self] in
				do { try await Task.sleep(for: .seconds(20)) } catch { return }
				self?.finish(.failure(BrowserAIError.pageUnavailable))
			}
			defer { timeout.cancel() }
			try await withCheckedThrowingContinuation { continuation in
				completion = continuation
				webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
			}
			try Task.checkCancellation()
			if let earlyPage {
				return earlyPage
			}
			return try await BrowserAIPageText.extract(from: webView)
		} onCancel: {
			Task { @MainActor in
				self.finish(.failure(CancellationError()))
				self.webView.stopLoading()
			}
		}
	}

	private static let previewReadinessScript = #"""
	(() => {
	    let reported = false;
	    const observer = new MutationObserver(report);
	    function report() {
	        if (reported) return;
	        const root = document.querySelector('article, main, [role="main"]') || document.body;
	        const ready = Array.from(root?.querySelectorAll('p, li, blockquote, pre') || []).some(block =>
	            !block.closest('nav, header, footer, aside') && block.innerText.trim().length >= 80);
	        if (!ready) return;
	        reported = true;
	        observer.disconnect();
	        window.webkit.messageHandlers.aiPreviewPageReady.postMessage(null);
	    }
	    observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
	    report();
	})();
	"""#

	func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
		guard message.frameInfo.isMainFrame, message.webView === webView,
		      completion != nil, earlyExtraction == nil else { return }
		earlyExtraction = Task { @MainActor in
			if let page = try? await BrowserAIPageText.extract(from: webView), !Task.isCancelled, completion != nil {
				earlyPage = page
				finish(.success(()))
			}
		}
	}

	private static func allowed(_ url: URL) -> Bool {
		["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil && url.user == nil && url.password == nil
	}

	func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
		if action.targetFrame?.isMainFrame == false {
			let allowed = action.request.url.map { Self.allowed($0) || $0.absoluteString == "about:blank" } ?? false
			decisionHandler(allowed ? .allow : .cancel)
			return
		}
		guard let url = action.request.url, Self.allowed(url), action.navigationType == .other else {
			decisionHandler(.cancel)
			finish(.failure(BrowserAIError.pageUnavailable))
			return
		}
		decisionHandler(.allow)
	}

	func webView(_: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
		guard response.isForMainFrame else {
			decisionHandler(response.canShowMIMEType ? .allow : .cancel)
			return
		}
		guard response.canShowMIMEType, response.response.mimeType?.contains("html") == true else {
			decisionHandler(.cancel)
			finish(.failure(BrowserAIError.pageUnavailable))
			return
		}
		decisionHandler(.allow)
	}

	func webView(_: WKWebView, didFinish _: WKNavigation!) {
		finish(.success(()))
	}

	func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
		finish(.failure(error))
	}

	func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
		finish(.failure(error))
	}

	private func finish(_ result: Result<Void, Error>) {
		completion?.resume(with: result)
		completion = nil
	}
}
