#if os(macOS)
	import AppKit
	import WebKit

	@MainActor
	enum BrowserWebsiteUI {
		private static var presentations: [ObjectIdentifier: (id: UUID, task: Task<NSApplication.ModalResponse, Never>)] = [:]

		static func present(
			_ alert: NSAlert,
			in window: NSWindow?,
			isCurrent: @escaping @MainActor () -> Bool = { true }
		) async -> NSApplication.ModalResponse {
			guard let window else { return .abort }
			let key = ObjectIdentifier(window)
			let previous = presentations[key]?.task
			let id = UUID()
			let task = Task { @MainActor [weak window] in
				_ = await previous?.value
				guard let window else { return NSApplication.ModalResponse.abort }
				while window.attachedSheet != nil {
					guard window.isVisible, isCurrent(), !Task.isCancelled else { return .abort }
					do {
						try await Task.sleep(for: .milliseconds(100))
					} catch {
						return .abort
					}
				}
				guard window.isVisible, isCurrent(), !Task.isCancelled else { return .abort }
				let monitor = Task { @MainActor in
					while !Task.isCancelled {
						if !isCurrent() || !window.isVisible {
							if window.attachedSheet === alert.window {
								window.endSheet(alert.window, returnCode: .abort)
							}
							return
						}
						do {
							try await Task.sleep(for: .milliseconds(100))
						} catch {
							return
						}
					}
				}
				defer { monitor.cancel() }
				let response = await withCheckedContinuation { continuation in
					alert.beginSheetModal(for: window) { response in
						continuation.resume(returning: response)
					}
				}
				return isCurrent() ? response : .abort
			}
			presentations[key] = (id, task)
			let response = await task.value
			if presentations[key]?.id == id {
				presentations[key] = nil
			}
			return response
		}

		static func alert(title: String, message: String, confirm: String, cancel: String? = "Cancel") -> NSAlert {
			let alert = NSAlert()
			alert.messageText = title
			alert.informativeText = String(message.prefix(4000))
			alert.addButton(withTitle: confirm)
			if let cancel {
				alert.addButton(withTitle: cancel)
			}
			return alert
		}

		static func authenticate(
			_ challenge: URLAuthenticationChallenge,
			in window: NSWindow?,
			isCurrent: @escaping @MainActor () -> Bool = { true }
		) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
			let method = challenge.protectionSpace.authenticationMethod
			guard [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodDefault].contains(method) else {
				return (.performDefaultHandling, nil)
			}
			guard challenge.previousFailureCount < 3 else {
				return (.cancelAuthenticationChallenge, nil)
			}
			let alert = alert(
				title: "Sign in to \(challenge.protectionSpace.host)",
				message: challenge.protectionSpace.protocol == "https"
					? "This website requires a username and password."
					: "This connection is not encrypted. Your credentials may be exposed.",
				confirm: "Sign In"
			)
			let username = NSTextField()
			username.placeholderString = "Username"
			username.setAccessibilityLabel("Username")
			let password = NSSecureTextField()
			password.placeholderString = "Password"
			password.setAccessibilityLabel("Password")
			let fields = NSStackView(views: [username, password])
			fields.orientation = .vertical
			fields.frame = NSRect(x: 0, y: 0, width: 320, height: 60)
			fields.alignment = .leading
			username.widthAnchor.constraint(equalTo: fields.widthAnchor).isActive = true
			password.widthAnchor.constraint(equalTo: fields.widthAnchor).isActive = true
			alert.accessoryView = fields
			alert.window.initialFirstResponder = username
			let response = await present(alert, in: window, isCurrent: isCurrent)
			if response == .alertFirstButtonReturn {
				return (.useCredential, URLCredential(
					user: username.stringValue,
					password: password.stringValue,
					persistence: .none
				))
			} else {
				return (.cancelAuthenticationChallenge, nil)
			}
		}
	}

	extension BrowserController {
		func webView(
			_ webView: WKWebView,
			runJavaScriptAlertPanelWithMessage message: String,
			initiatedByFrame frame: WKFrameInfo,
			completionHandler: @escaping () -> Void
		) {
			let documentID = navigationIdentifier
			Task { @MainActor in
				let alert = BrowserWebsiteUI.alert(
					title: frame.securityOrigin.host,
					message: message,
					confirm: "OK",
					cancel: nil
				)
				_ = await BrowserWebsiteUI.present(alert, in: webView.window) { [self] in
					navigationIdentifier == documentID
				}
				completionHandler()
			}
		}

		func webView(
			_ webView: WKWebView,
			runJavaScriptConfirmPanelWithMessage message: String,
			initiatedByFrame frame: WKFrameInfo,
			completionHandler: @escaping (Bool) -> Void
		) {
			let documentID = navigationIdentifier
			Task { @MainActor in
				let alert = BrowserWebsiteUI.alert(title: frame.securityOrigin.host, message: message, confirm: "OK")
				let response = await BrowserWebsiteUI.present(alert, in: webView.window) { [self] in
					navigationIdentifier == documentID
				}
				completionHandler(response == .alertFirstButtonReturn)
			}
		}

		func webView(
			_ webView: WKWebView,
			runJavaScriptTextInputPanelWithPrompt prompt: String,
			defaultText: String?,
			initiatedByFrame frame: WKFrameInfo,
			completionHandler: @escaping (String?) -> Void
		) {
			let documentID = navigationIdentifier
			Task { @MainActor in
				let alert = BrowserWebsiteUI.alert(title: frame.securityOrigin.host, message: prompt, confirm: "OK")
				let field = NSTextField(string: defaultText ?? "")
				field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
				field.setAccessibilityLabel(prompt)
				alert.accessoryView = field
				alert.window.initialFirstResponder = field
				let response = await BrowserWebsiteUI.present(alert, in: webView.window) { [self] in
					navigationIdentifier == documentID
				}
				completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
			}
		}

		func webView(
			_ webView: WKWebView,
			runBeforeUnloadConfirmPanelWithMessage _: String,
			initiatedByFrame frame: WKFrameInfo,
			completionHandler: @escaping (Bool) -> Void
		) {
			let documentID = navigationIdentifier
			Task { @MainActor in
				let alert = BrowserWebsiteUI.alert(
					title: "Leave \(frame.securityOrigin.host)?",
					message: "Changes you made may not be saved.",
					confirm: "Leave",
					cancel: "Stay"
				)
				let response = await BrowserWebsiteUI.present(alert, in: webView.window) { [self] in
					navigationIdentifier == documentID
				}
				completionHandler(response == .alertFirstButtonReturn)
			}
		}

		func webView(
			_ webView: WKWebView,
			runOpenPanelWith parameters: WKOpenPanelParameters,
			initiatedByFrame frame: WKFrameInfo,
			completionHandler: @escaping ([URL]?) -> Void
		) {
			guard let window = webView.window, window.attachedSheet == nil else {
				completionHandler(nil)
				return
			}
			let documentID = navigationIdentifier
			let panel = NSOpenPanel()
			panel.message = "Choose files for \(frame.securityOrigin.host)"
			panel.allowsMultipleSelection = parameters.allowsMultipleSelection
			panel.canChooseDirectories = parameters.allowsDirectories
			panel.canChooseFiles = true
			let monitor = Task { @MainActor [weak self, weak window] in
				while !Task.isCancelled {
					guard self?.navigationIdentifier == documentID, window?.isVisible == true else {
						panel.cancel(nil)
						return
					}
					do {
						try await Task.sleep(for: .milliseconds(100))
					} catch {
						return
					}
				}
			}
			panel.beginSheetModal(for: window) { [weak self, weak window] response in
				monitor.cancel()
				let isCurrent = self?.navigationIdentifier == documentID && window?.isVisible == true
				completionHandler(response == .OK && isCurrent ? panel.urls : nil)
			}
		}

		func webView(
			_ webView: WKWebView,
			requestMediaCapturePermissionFor origin: WKSecurityOrigin,
			initiatedByFrame _: WKFrameInfo,
			type: WKMediaCaptureType,
			decisionHandler: @escaping (WKPermissionDecision) -> Void
		) {
			let capabilities: [BrowserSitePermissions.Capability]
			switch type {
				case .camera: capabilities = [.camera]
				case .microphone: capabilities = [.microphone]
				case .cameraAndMicrophone: capabilities = [.camera, .microphone]
				@unknown default:
					decisionHandler(.deny)
					return
			}
			Task { @MainActor in
				let decision = await requestPermission(capabilities, origin: origin, in: webView)
				decisionHandler(decision)
			}
		}

		func webView(
			_ webView: WKWebView,
			requestGeolocationPermissionFor origin: WKSecurityOrigin,
			initiatedByFrame _: WKFrameInfo,
			decisionHandler: @escaping (WKPermissionDecision) -> Void
		) {
			Task { @MainActor in
				let decision = await requestPermission([.location], origin: origin, in: webView)
				decisionHandler(decision)
			}
		}

		private func requestPermission(
			_ capabilities: [BrowserSitePermissions.Capability],
			origin: WKSecurityOrigin,
			in webView: WKWebView
		) async -> WKPermissionDecision {
			var parts = URLComponents()
			parts.scheme = origin.protocol
			parts.host = origin.host
			parts.port = origin.port > 0 ? origin.port : nil
			guard let originURL = parts.url,
			      let originID = BrowserSitePermissions.origin(for: originURL),
			      let topURL = webView.url,
			      let topOrigin = BrowserSitePermissions.origin(for: topURL),
			      origin.protocol == "https" || ["localhost", "127.0.0.1", "::1"].contains(origin.host)
			else { return .deny }
			guard let window = webView.window, window.isVisible else { return .deny }
			let documentID = navigationIdentifier
			let permissions = session.permissions
			let decisions = capabilities.map {
				permissions.decision(origin: originID, topOrigin: topOrigin, capability: $0)
			}
			if decisions.contains(false) {
				return .deny
			}
			if decisions.allSatisfy({ $0 == true }) {
				return .grant
			}
			let title = capabilities.map(\.title).joined(separator: " and ")
			let alert = BrowserWebsiteUI.alert(
				title: "Allow \(originID) to access \(title.lowercased())?",
				message: originID == topOrigin
					? "You can reset this website's permissions in Privacy and Security settings."
					: "This request comes from content embedded in \(topOrigin).",
				confirm: "Allow",
				cancel: "Don't Allow"
			)
			let response = await BrowserWebsiteUI.present(alert, in: webView.window) { [weak self, weak webView] in
				self?.navigationIdentifier == documentID && webView?.window?.isVisible == true
			}
			guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return .deny }
			guard webView.url.flatMap(BrowserSitePermissions.origin(for:)) == topOrigin else { return .deny }
			let allowed = response == .alertFirstButtonReturn
			for capability in capabilities {
				permissions.set(allowed, origin: originID, topOrigin: topOrigin, capability: capability)
			}
			return allowed ? .grant : .deny
		}

		func webViewDidClose(_: WKWebView) {
			closeRequested?()
		}

		func webView(
			_ webView: WKWebView,
			didReceive challenge: URLAuthenticationChallenge,
			completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
		) {
			let documentID = navigationIdentifier
			Task { @MainActor in
				let response = await BrowserWebsiteUI.authenticate(challenge, in: webView.window) { [self] in
					navigationIdentifier == documentID
				}
				completionHandler(response.0, response.1)
			}
		}
	}
#endif
