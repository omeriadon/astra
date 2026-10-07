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
			BrowserLog.info(.navigation, "auth-session.begin", metadata: ["id": BrowserLog.id(request.uuid), "url": BrowserLog.url(request.url), "ephemeral": String(request.shouldUseEphemeralSession)])
			if let replaced = sessions.removeValue(forKey: request.uuid) {
				replaced.request.cancelWithError(Self.cancellationError)
				closeAndCleanUp(replaced)
			}
			guard request.callback != nil,
			      let initialRequest = BrowserAuthenticationPolicy.initialRequest(
			      	url: request.url,
			      	headers: request.additionalHeaderFields
			      )
			else {
				request.cancelWithError(Self.cancellationError)
				return
			}
			let browser = Browser(isMini: true, isPrivate: request.shouldUseEphemeralSession)
			let window = BrowserWindowController(browser: browser)
			let id = request.uuid
			let session = Session(generation: UUID(), request: request, window: window)
			let generation = session.generation
			let webSession = browser.session
			sessions[id] = session
			let controller = browser.selectedTab?.controller
			controller?.isAuthenticationSessionBrowser = true
			browser.navigationIntercept = { [weak self, weak request, weak window] url in
				guard let self,
				      let request,
				      let window,
				      let current = sessions[id],
				      BrowserAuthenticationPolicy.isCurrentSession(
				      	generation: generation,
				      	currentGeneration: current.generation,
				      	sameRequest: current.request === request,
				      	sameWindow: current.window === window
				      ),
				      request.callback?.matchesURL(url) == true else { return false }
				sessions[id] = nil
				request.complete(withCallbackURL: url)
				window.window.close()
				cleanUpPrivateSession(webSession)
				return true
			}
			window.onClose = { [weak self, weak window] in
				guard let self else { return }
				defer { cleanUpPrivateSession(webSession) }
				if let current = sessions[id],
				   BrowserAuthenticationPolicy.isCurrentSession(
				   	generation: generation,
				   	currentGeneration: current.generation,
				   	sameRequest: true,
				   	sameWindow: current.window === window
				   )
				{
					sessions[id] = nil
					current.request.cancelWithError(Self.cancellationError)
				}
			}
			controller?.navigate(initialRequest)
			window.showWindow()
			NSApp.activate()
		}

		func cancel(_ request: ASWebAuthenticationSessionRequest) {
			BrowserLog.notice(.navigation, "auth-session.cancel", metadata: ["id": BrowserLog.id(request.uuid)])
			guard let session = sessions[request.uuid], session.request === request else { return }
			sessions[request.uuid] = nil
			closeAndCleanUp(session)
		}

		func cancelAll() async {
			BrowserLog.notice(.navigation, "auth-session.cancel-all", metadata: ["count": String(sessions.count)])
			let pending = Array(sessions.values)
			sessions.removeAll()
			for session in pending {
				session.request.cancelWithError(Self.cancellationError)
				session.window.window.close()
				await session.window.browser.session.endPrivateSession()
			}
		}

		private func closeAndCleanUp(_ session: Session) {
			BrowserLog.debug(.navigation, "auth-session.cleanup", metadata: ["id": BrowserLog.id(session.request.uuid)])
			session.window.window.close()
			cleanUpPrivateSession(session.window.browser.session)
		}

		private func cleanUpPrivateSession(_ session: BrowserWebSession) {
			guard session.isPrivate else { return }
			Task { await session.endPrivateSession() }
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
