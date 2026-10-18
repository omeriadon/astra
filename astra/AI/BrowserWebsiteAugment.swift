import Foundation
import SwiftUI
import WebKit

/// The complete local result is persisted with chat; HTML is never included in a tool response.
nonisolated struct BrowserWebsiteAugmentArtifact: Codable, Identifiable, Sendable {
	let id: UUID
	let title: String
	let sourceURL: URL
	let html: String
	let createdAt: Date
}

#if !ASTRA_WEBSITE_APP_RUNTIME
	@MainActor
	enum BrowserWebsiteAugment {
		static func inspect(tab: BrowserTab, selector: String? = nil, offset: Int = 0, limit: Int = 12) async throws -> String {
			guard let controller = tab.activeController, let webView = controller.webViewIfLoaded, !webView.isLoading else { throw BrowserAIError.pageUnavailable }
			let generation = controller.navigationIdentifier
			let result = try await webView.callAsyncJavaScript(structureScript, arguments: ["selector": selector ?? "", "offset": max(0, offset), "limit": min(30, max(1, limit))], in: nil, contentWorld: .defaultClient)
			guard tab.activeController === controller, controller.navigationIdentifier == generation, !Task.isCancelled, let text = result as? String else { throw BrowserAIError.pageUnavailable }
			return text
		}

		static func apply(arguments: [String: String], browser: Browser) async throws -> BrowserWebsiteAugmentArtifact {
			let tab: BrowserTab?
			if let raw = arguments["tabID"] {
				guard let id = UUID(uuidString: raw) else { throw BrowserAIError.invalidRequest }
				tab = browser.visibleTabs.first { $0.id == id }
			} else {
				tab = browser.selectedTab
			}
			guard let tab, tab.internalPage == nil, let controller = tab.activeController,
			      let view = controller.webViewIfLoaded, !view.isLoading,
			      let sourceURL = controller.snapshotSourceURL ?? view.url, ["http", "https"].contains(sourceURL.scheme?.lowercased() ?? ""),
			      let operations = arguments["operations"], operations.utf8.count <= 65536,
			      let data = operations.data(using: .utf8), let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
			      !array.isEmpty, array.count <= 100 else { throw BrowserAIError.invalidRequest }
			let generation = controller.navigationIdentifier
			guard let html = try await view.callAsyncJavaScript(captureScript, arguments: [:], in: nil, contentWorld: .defaultClient) as? String,
			      html.utf8.count <= 12_000_000, tab.activeController === controller, controller.navigationIdentifier == generation else { throw BrowserAIError.pageUnavailable }
			let runner = BrowserWebsiteAugmentRunner()
			let result = try await runner.transform(html: html, source: sourceURL, operations: array)
			guard !Task.isCancelled, tab.activeController === controller, controller.navigationIdentifier == generation,
			      browser.visibleTabs.contains(where: { $0 === tab }) else { throw BrowserAIError.pageUnavailable }
			let title = String((arguments["title"] ?? "Augmented \(tab.title)").prefix(200))
			return BrowserWebsiteAugmentArtifact(id: UUID(), title: title, sourceURL: BrowserAddress.withoutCredentials(sourceURL), html: result, createdAt: Date())
		}

		static func open(_ artifact: BrowserWebsiteAugmentArtifact, in browser: Browser) throws {
			guard let tab = browser.selectedTab, artifact.html.utf8.count <= 12_000_000 else { throw BrowserAIError.pageUnavailable }
			let configuration = WKWebViewConfiguration()
			configuration.defaultWebpagePreferences.allowsContentJavaScript = false
			let controller = BrowserController(session: BrowserWebSession(isPrivate: true), configuration: configuration)
			// A fresh private session ensures remote images/styles cannot inherit website cookies.
			// The artifact CSP disables page scripts, forms, frames and outbound connections.
			controller.snapshotNavigationOnly = true
			controller.snapshotSourceURL = artifact.sourceURL
			controller.webView.loadHTMLString(artifact.html, baseURL: nil)
			let peek = BrowserPeek(depth: tab.peeks.count + 1, source: .trailing, parentZoom: 1, zoomsOut: false, existingController: controller)
			tab.addPeek(peek)
		}

		static let structureScript = #"""
		const compact = value => String(value || '').replace(/\s+/g, ' ').trim();
		const sensitive = 'script,style,noscript,template,input,textarea,select,[contenteditable],iframe,object,embed';
		const visible = el => !el.closest(sensitive) && !el.closest('[hidden],[aria-hidden="true"]') && getComputedStyle(el).display !== 'none' && getComputedStyle(el).visibility !== 'hidden';
		function path(el) {
		    if (el.id) return '#' + CSS.escape(el.id);
		    const parts = [];
		    while (el && el !== document.body && parts.length < 40) {
		        let part = el.localName;
		        if (el.id) { parts.unshift('#' + CSS.escape(el.id)); break; }
		        const siblings = el.parentElement ? [...el.parentElement.children].filter(n => n.localName === el.localName) : [];
		        if (siblings.length > 1) part += ':nth-of-type(' + (siblings.indexOf(el) + 1) + ')';
		        parts.unshift(part); el = el.parentElement;
		    }
		    return parts.length ? (el === document.body ? 'body > ' : '') + parts.join(' > ') : 'body';
		}
		function summary(el) {
		    const walker = document.createTreeWalker(el, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
		        acceptNode(node) {
		            if (node.nodeType === 1) return node.matches(sensitive + ',[hidden],[aria-hidden="true"]') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_SKIP;
		            return NodeFilter.FILTER_ACCEPT;
		        }
		    });
		    let text = '', node;
		    while (text.length < 320 && (node = walker.nextNode())) text += ' ' + compact(node.nodeValue).slice(0, 320 - text.length);
		    return {selector: path(el), tag: el.localName, role: el.getAttribute('role'), classes: [...el.classList].slice(0,6), children: el.children.length, text: compact(text).slice(0, 320)};
		}
		let matches;
		try { matches = [...document.querySelectorAll(selector || 'main,article,section,nav,header,footer,aside,h1,h2,h3,ul,ol,table,[role="main"]')].filter(visible); }
		catch { throw new Error('Invalid selector'); }
		const items = matches.slice(offset, offset + limit).map(el => {
		    const item = summary(el);
		    if (el.matches('ul,ol,table,[role="list"],[role="grid"]')) {
		        const rows = [...el.querySelectorAll('li,tr,[role="listitem"],[role="row"]')].filter(visible);
		        item.itemCount = rows.length;
		        item.samples = rows.slice(0,3).map(summary);
		    }
		    return item;
		});
		while (items.length > 1 && JSON.stringify(items).length > 16000) items.pop();
		const next = offset + items.length;
		return JSON.stringify({title: document.title.slice(0,200), url: location.origin + location.pathname, total: matches.length, offset, nextOffset: next < matches.length ? next : null, items});
		"""#

		static let captureScript = #"""
		const root = document.documentElement.cloneNode(true);
		root.querySelectorAll('script,noscript,iframe,frame,object,embed,applet,base,meta[http-equiv],input,textarea,select,[contenteditable]').forEach(n => n.remove());
		root.querySelectorAll('form').forEach(form => form.replaceWith(...form.childNodes));
		for (const el of [root, ...root.querySelectorAll('*')]) {
		    for (const attr of [...el.attributes]) {
		        if (/^on/i.test(attr.name) || /^(nonce|integrity|autofocus|ping|srcdoc|action|formaction)$/i.test(attr.name)) el.removeAttribute(attr.name);
		    }
		    for (const name of ['href','src','poster','xlink:href']) {
		        if (!el.hasAttribute(name)) continue;
		        try {
		            const url = new URL(el.getAttribute(name), document.baseURI);
		            if (!['http:','https:','data:'].includes(url.protocol) || url.username || url.password) el.removeAttribute(name);
		            else el.setAttribute(name, url.href);
		        } catch { el.removeAttribute(name); }
		    }
		}
		return '<!doctype html>' + root.outerHTML;
		"""#

		static let transformScript = #"""
		const doc = new DOMParser().parseFromString(html, 'text/html');
		const forbidden = 'script,noscript,iframe,frame,object,embed,applet,base,meta[http-equiv],form,input,textarea,select';
		const css = new Map([...doc.querySelectorAll('style,link[rel~="stylesheet"]')].map(n => [n, n.outerHTML]));
		const inline = new Map([...doc.querySelectorAll('[style]')].map(n => [n, n.getAttribute('style')]));
		function validate() {
		    if (doc.querySelector(forbidden)) throw new Error('Active content is not allowed');
		    for (const el of doc.querySelectorAll('*')) {
		        if ([...el.attributes].some(a => /^on/i.test(a.name) || /^(srcdoc|action|formaction|ping)$/i.test(a.name))) throw new Error('Active attributes are not allowed');
		        if (el.hasAttribute('style') && inline.get(el) !== el.getAttribute('style')) throw new Error('New or modified CSS is not allowed');
		        for (const name of ['href','src','poster','xlink:href']) {
		            if (!el.hasAttribute(name)) continue;
		            const url = new URL(el.getAttribute(name), source);
		            if (!['https:','http:','data:'].includes(url.protocol) || url.username || url.password) throw new Error('Unsafe URL');
		            el.setAttribute(name, url.href);
		        }
		    }
		    for (const el of doc.querySelectorAll('style,link[rel~="stylesheet"]')) {
		        if (css.get(el) !== el.outerHTML) throw new Error('New or modified CSS is not allowed');
		    }
		    for (const [el, value] of inline) if (el.isConnected && el.getAttribute('style') !== value) throw new Error('Existing CSS must be preserved');
		    for (const [el, value] of css) if (!el.isConnected || el.outerHTML !== value) throw new Error('Existing CSS must be preserved');
		}
		for (const op of operations) {
		    if (!op || typeof op.action !== 'string') throw new Error('Missing action');
		    if (op.action === 'javascript') {
		        if (typeof op.code !== 'string' || op.code.length > 32000) throw new Error('Invalid JavaScript');
		        // This function only receives a detached document in a network-blocked, bridge-free webview.
		        new Function('document', '"use strict";\n' + op.code)(doc);
		    } else {
		        if (typeof op.selector !== 'string' || !op.selector || op.selector.length > 2000) throw new Error('Missing selector');
		        const nodes = [...doc.querySelectorAll(op.selector)].filter(n => !n.matches('html,head,body,style,link'));
		        if (!nodes.length) throw new Error('Selector matched no editable elements');
		        switch (op.action) {
		        case 'remove': nodes.forEach(n => n.remove()); break;
		        case 'keep': {
		            const retained = new Set();
		            for (const node of nodes) { for (let n = node; n; n = n.parentElement) retained.add(n); node.querySelectorAll('*').forEach(n => retained.add(n)); }
		            doc.body.querySelectorAll('*').forEach(n => { if (!retained.has(n) && !n.matches('style,link[rel~="stylesheet"]') && !n.querySelector('style,link[rel~="stylesheet"]')) n.remove(); });
		            break;
		        }
		        case 'filter':
		            if (typeof op.contains !== 'string') throw new Error('Filter requires contains');
		            nodes.forEach(n => { if (n.textContent.toLocaleLowerCase().includes(op.contains.toLocaleLowerCase()) === !!op.exclude) n.remove(); }); break;
		        case 'replace':
		            if (typeof op.text === 'string') nodes.forEach(n => n.textContent = op.text);
		            else if (typeof op.html === 'string') nodes.forEach(n => { const template = doc.createElement('template'); template.innerHTML = op.html; n.replaceWith(template.content.cloneNode(true)); });
		            else throw new Error('Replace requires html or text');
		            break;
		        default: throw new Error('Unknown augmentation action');
		        }
		    }
		    validate();
		}
		validate();
		return '<!doctype html>' + doc.documentElement.outerHTML;
		"""#

		/// Reparse in a separate JS realm after untrusted JavaScript has finished. Its
		/// prototype changes cannot bypass these checks or replace the security policy.
		static let finalizeScript = #"""
		const doc = new DOMParser().parseFromString(result, 'text/html');
		const original = new DOMParser().parseFromString(html, 'text/html');
		const styles = d => [...d.querySelectorAll('style,link[rel~="stylesheet"]')].map(n => n.outerHTML).sort();
		if (JSON.stringify(styles(doc)) !== JSON.stringify(styles(original))) throw new Error('Existing CSS must be preserved');
		const available = new Map();
		for (const el of original.querySelectorAll('[style]')) { const value = el.getAttribute('style'); available.set(value, (available.get(value) || 0) + 1); }
		for (const el of [...doc.querySelectorAll('*')]) {
		    if (el.matches('script,noscript,iframe,frame,object,embed,applet,base,meta[http-equiv],form,input,textarea,select')) throw new Error('Active content is not allowed');
		    if ([...el.attributes].some(a => /^on/i.test(a.name) || /^(srcdoc|action|formaction|ping)$/i.test(a.name))) throw new Error('Active attributes are not allowed');
		    if (el.hasAttribute('style')) { const value = el.getAttribute('style'); const count = available.get(value) || 0; if (!count) throw new Error('New CSS is not allowed'); available.set(value, count - 1); }
		    for (const name of ['href','src','poster','xlink:href']) {
		        if (!el.hasAttribute(name)) continue;
		        const url = new URL(el.getAttribute(name), source);
		        if (!['http:','https:','data:'].includes(url.protocol) || url.username || url.password) throw new Error('Unsafe URL');
		        el.setAttribute(name, url.href);
		    }
		}
		const base = doc.createElement('base'); base.href = source; doc.head.prepend(base);
		const policy = doc.createElement('meta'); policy.httpEquiv = 'Content-Security-Policy';
		policy.content = "default-src 'none'; script-src 'none'; style-src https: http: 'unsafe-inline'; img-src https: http: data:; font-src https: http: data:; media-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri https: http:";
		doc.head.prepend(policy);
		const referrer = doc.createElement('meta'); referrer.name = 'referrer'; referrer.content = 'no-referrer'; doc.head.prepend(referrer);
		return '<!doctype html>' + doc.documentElement.outerHTML;
		"""#
	}

	/// Generated code never runs in the source tab, preview, or a browser-session web view.
	@MainActor
	private final class BrowserWebsiteAugmentRunner: NSObject, WKNavigationDelegate {
		private var view: WKWebView?
		private var continuation: CheckedContinuation<String, Error>?
		private var inputs: [String: Any] = [:]
		private var timeout: Task<Void, Never>?

		func transform(html: String, source: URL, operations: [[String: Any]]) async throws -> String {
			let configuration = WKWebViewConfiguration()
			configuration.websiteDataStore = .nonPersistent()
			let rules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
			let rule = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "astra-augment-offline-v1", encodedContentRuleList: rules)
			guard let rule else { throw BrowserAIError.pageUnavailable }
			try Task.checkCancellation()
			configuration.userContentController.add(rule)
			let view = WKWebView(frame: .zero, configuration: configuration)
			self.view = view
			view.navigationDelegate = self
			inputs = ["html": html, "source": BrowserAddress.withoutCredentials(source).absoluteString, "operations": operations]
			return try await withTaskCancellationHandler {
				try Task.checkCancellation()
				return try await withCheckedThrowingContinuation { continuation in
					self.continuation = continuation
					timeout = Task { [weak self] in
						do { try await Task.sleep(for: .seconds(12)) } catch { return }
						self?.finish(.failure(BrowserAIError.pageUnavailable))
					}
					view.loadHTMLString("<!doctype html><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; connect-src 'none'; form-action 'none'\"><title>Offline augmentation</title>", baseURL: nil)
				}
			} onCancel: {
				Task { @MainActor in self.finish(.failure(CancellationError())) }
			}
		}

		private func finish(_ result: Result<String, Error>) {
			timeout?.cancel(); timeout = nil
			view?.stopLoading(); view?.navigationDelegate = nil; view = nil
			inputs = [:]
			let pending = continuation; continuation = nil
			pending?.resume(with: result)
		}

		func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
			decisionHandler(action.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
		}

		func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
			guard continuation != nil else { return }
			webView.callAsyncJavaScript(BrowserWebsiteAugment.transformScript, arguments: inputs, in: nil, in: .defaultClient) { [weak self] result in
				guard let self, continuation != nil else { return }
				switch result {
					case let .failure(error): finish(.failure(error))
					case let .success(value):
						guard let text = value as? String, text.utf8.count <= 12_000_000 else { finish(.failure(BrowserAIError.invalidRequest)); return }
						var arguments = inputs
						arguments["result"] = text
						view?.callAsyncJavaScript(BrowserWebsiteAugment.finalizeScript, arguments: arguments, in: nil, in: .world(name: "AstraAugmentValidation")) { [weak self] checked in
							guard let self, continuation != nil else { return }
							switch checked {
								case let .failure(error): finish(.failure(error))
								case let .success(output):
									guard let html = output as? String, html.utf8.count <= 12_000_000 else { finish(.failure(BrowserAIError.invalidRequest)); return }
									finish(.success(html))
							}
						}
				}
			}
		}

		func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
			finish(.failure(error))
		}

		func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
			finish(.failure(error))
		}
	}

#endif
