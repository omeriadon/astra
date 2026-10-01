#if os(macOS)
	import AppKit
	import AuthenticationServices

	@MainActor
	final class BrowserAuthenticationSessionHandler: NSObject, ASWebAuthenticationSessionWebBrowserSessionHandling {
		static let shared = BrowserAuthenticationSessionHandler()

		private struct Session {
			let request: ASWebAuthenticationSessionRequest
			let window: BrowserWindowController
		}

		private var sessions: [UUID: Session] = [:]

		var activeBrowser: Browser? {
			sessions.values.first { $0.window.window === NSApp.keyWindow }?.window.browser
		}

		func begin(_ request: ASWebAuthenticationSessionRequest) {
			guard ["http", "https"].contains(request.url.scheme?.lowercased() ?? ""),
			      request.callback != nil
			else {
				request.cancelWithError(Self.cancellationError)
				return
			}
			cancel(request)
			let browser = Browser(isMini: true, isPrivate: request.shouldUseEphemeralSession)
			let window = BrowserWindowController(browser: browser)
			let id = request.uuid
			sessions[id] = Session(request: request, window: window)
			browser.navigationIntercept = { [weak self] url in
				guard let self, let session = sessions[id],
				      session.request.callback?.matchesURL(url) == true else { return false }
				sessions[id] = nil
				session.request.complete(withCallbackURL: url)
				session.window.window.close()
				return true
			}
			window.onClose = { [weak self] in
				guard let session = self?.sessions.removeValue(forKey: id) else { return }
				session.request.cancelWithError(Self.cancellationError)
			}
			window.showWindow()
			NSApp.activate()
			var initial = URLRequest(url: request.url)
			let reservedHeaders = Set(["cookie", "host", "user-agent", "origin", "referer"])
			for (name, value) in request.additionalHeaderFields ?? [:] {
				guard !reservedHeaders.contains(name.lowercased()),
				      initial.value(forHTTPHeaderField: name) == nil else { continue }
				initial.setValue(value, forHTTPHeaderField: name)
			}
			browser.selectedTab?.controller?.navigate(initial)
		}

		func cancel(_ request: ASWebAuthenticationSessionRequest) {
			guard let session = sessions.removeValue(forKey: request.uuid) else { return }
			session.window.window.close()
		}

		func cancelAll() async {
			let pending = Array(sessions.values)
			sessions.removeAll()
			for session in pending {
				session.request.cancelWithError(Self.cancellationError)
				session.window.window.close()
				if session.window.browser.isPrivate {
					await session.window.browser.session.endPrivateSession()
				}
			}
		}

		private static var cancellationError: NSError {
			NSError(
				domain: ASWebAuthenticationSessionErrorDomain,
				code: ASWebAuthenticationSessionError.canceledLogin.rawValue,
				userInfo: [NSLocalizedDescriptionKey: "The authentication session was canceled."]
			)
		}
	}
#endif
