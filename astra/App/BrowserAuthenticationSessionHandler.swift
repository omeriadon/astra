#if os(macOS)
	import AppKit
	import AuthenticationServices

	@MainActor
	final class BrowserAuthenticationSessionHandler: NSObject, ASWebAuthenticationSessionWebBrowserSessionHandling {
		static let shared = BrowserAuthenticationSessionHandler()

		private struct Session {
			let generation: UUID
			let request: ASWebAuthenticationSessionRequest
			let window: BrowserWindowController
		}

		private var sessions: [UUID: Session] = [:]

		var activeBrowser: Browser? {
			sessions.values.first { $0.window.window === NSApp.keyWindow }?.window.browser
		}

		func begin(_ request: ASWebAuthenticationSessionRequest) {
			if let replaced = sessions.removeValue(forKey: request.uuid) {
				replaced.request.cancelWithError(Self.cancellationError)
				closeAndCleanUp(replaced)
			}
			guard request.callback != nil,
			      let initialRequest = BrowserAuthenticationPolicy.initialRequest(
				      url: request.url,
				      headers: request.additionalHeaderFields
			      ) else {
				request.cancelWithError(Self.cancellationError)
				return
			}
			let browser = Browser(isMini: true, isPrivate: request.shouldUseEphemeralSession)
			let window = BrowserWindowController(browser: browser)
			let id = request.uuid
			let session = Session(generation: UUID(), request: request, window: window)
			sessions[id] = session
			let controller = browser.selectedTab?.controller
			controller?.isAuthenticationSessionBrowser = true
			browser.navigationIntercept = { [weak self] url in
				guard let self,
				      let current = sessions[id],
				      BrowserAuthenticationPolicy.isCurrentSession(
					      generation: session.generation,
					      currentGeneration: current.generation,
					      sameRequest: current.request === request,
					      sameWindow: current.window === window
				      ),
				      request.callback?.matchesURL(url) == true else { return false }
				sessions[id] = nil
				request.complete(withCallbackURL: url)
				closeAndCleanUp(session)
				return true
			}
			window.onClose = { [weak self] in
				guard let self else { return }
				if let current = sessions[id],
				   BrowserAuthenticationPolicy.isCurrentSession(
					   generation: session.generation,
					   currentGeneration: current.generation,
					   sameRequest: current.request === request,
					   sameWindow: current.window === window
				   )
				{
					sessions[id] = nil
					request.cancelWithError(Self.cancellationError)
				}
				cleanUpPrivateSession(session)
			}
			controller?.navigate(initialRequest)
			window.showWindow()
			NSApp.activate()
		}

		func cancel(_ request: ASWebAuthenticationSessionRequest) {
			guard let session = sessions[request.uuid], session.request === request else { return }
			sessions[request.uuid] = nil
			closeAndCleanUp(session)
		}

		func cancelAll() async {
			let pending = Array(sessions.values)
			sessions.removeAll()
			for session in pending {
				session.request.cancelWithError(Self.cancellationError)
				session.window.window.close()
				await session.window.browser.session.endPrivateSession()
			}
		}

		private func closeAndCleanUp(_ session: Session) {
			session.window.window.close()
			cleanUpPrivateSession(session)
		}

		private func cleanUpPrivateSession(_ session: Session) {
			guard session.window.browser.isPrivate else { return }
			Task { await session.window.browser.session.endPrivateSession() }
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
