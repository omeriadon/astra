import AVFoundation
import CoreLocation
import WebKit

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

		static func permissionPrompt(
			title: String,
			message: String,
			in webView: WKWebView,
			isCurrent: @escaping @MainActor () -> Bool
		) async -> BrowserSitePermissions.PromptResponse {
			let alert = alert(title: title, message: message, confirm: "Allow Once", cancel: "Don't Allow")
			alert.addButton(withTitle: "Always Allow")
			return switch await present(alert, in: webView.window, isCurrent: isCurrent) {
				case .alertFirstButtonReturn: BrowserSitePermissions.PromptResponse.allowOnce
				case .alertSecondButtonReturn: BrowserSitePermissions.PromptResponse.deny
				case .alertThirdButtonReturn: BrowserSitePermissions.PromptResponse.allowAlways
				default: BrowserSitePermissions.PromptResponse.cancel
			}
		}

		static func authenticate(
			_ challenge: URLAuthenticationChallenge,
			in window: NSWindow?,
			isCurrent: @escaping @MainActor () -> Bool = { true }
		) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
			switch BrowserAuthenticationPolicy.decision(
				method: challenge.protectionSpace.authenticationMethod,
				previousFailureCount: challenge.previousFailureCount
			) {
				case .cancel:
					return (.cancelAuthenticationChallenge, nil)
				case .useDefaultHandling:
					return (.performDefaultHandling, nil)
				case .prompt:
					break
			}
			let alert = alert(
				title: BrowserAuthenticationPolicy.title(
					host: challenge.protectionSpace.host,
					port: challenge.protectionSpace.port,
					realm: challenge.protectionSpace.realm
				),
				message: BrowserAuthenticationPolicy.isEncrypted(protocolName: challenge.protectionSpace.protocol)
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
					ownsPrompt(in: webView, documentID: documentID)
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
					ownsPrompt(in: webView, documentID: documentID)
				}
				completionHandler(response == .alertFirstButtonReturn && ownsPrompt(in: webView, documentID: documentID))
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
					ownsPrompt(in: webView, documentID: documentID)
				}
				completionHandler(response == .alertFirstButtonReturn && ownsPrompt(in: webView, documentID: documentID) ? field.stringValue : nil)
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
					ownsPrompt(in: webView, documentID: documentID)
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
			guard let window = webView.window,
			      ownsPrompt(in: webView, documentID: navigationIdentifier) else {
				completionHandler(nil)
				return
			}
			let documentID = navigationIdentifier
			let panel = NSOpenPanel()
			panel.message = "Choose files for \(frame.securityOrigin.host)"
			panel.allowsMultipleSelection = parameters.allowsMultipleSelection
			panel.canChooseDirectories = parameters.allowsDirectories
			panel.canChooseFiles = true
			var completed = false
			var monitor: Task<Void, Never>?
			let finish: ([URL]?) -> Void = { urls in
				guard !completed else { return }
				completed = true
				completionHandler(urls)
			}
			monitor = Task { @MainActor [weak self, weak window] in
				while let window, window.attachedSheet != nil {
					guard let self, ownsPrompt(in: webView, documentID: documentID), window.isVisible else {
						finish(nil)
						return
					}
					do {
						try await Task.sleep(for: .milliseconds(100))
					} catch {
						finish(nil)
						return
					}
				}
				guard let window else {
					finish(nil)
					return
				}
				guard let self, ownsPrompt(in: webView, documentID: documentID), window.isVisible else {
					finish(nil)
					return
				}
				panel.beginSheetModal(for: window) { [weak self, weak window] response in
					monitor?.cancel()
					let current = self?.ownsPrompt(in: webView, documentID: documentID) == true && window?.isVisible == true
					let selectedURLs = response == .OK ? panel.urls : []
					let urls = response == .OK && current ? selectedURLs : nil
					if current {
						self?.retainPanelUploadAccess(for: selectedURLs)
					} else {
						for url in selectedURLs {
							url.stopAccessingSecurityScopedResource()
						}
					}
					finish(urls)
				}
				while !Task.isCancelled {
					guard ownsPrompt(in: webView, documentID: documentID),
					      window.isVisible else {
						panel.cancel(nil)
						finish(nil)
						return
					}
					do {
						try await Task.sleep(for: .milliseconds(100))
					} catch {
						return
					}
				}
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
					ownsPrompt(in: webView, documentID: documentID)
				}
				guard ownsPrompt(in: webView, documentID: documentID) else {
					completionHandler(.cancelAuthenticationChallenge, nil)
					return
				}
				completionHandler(response.0, response.1)
			}
		}

	}
#endif

#if os(iOS)
	import UIKit
	import WebKit

	@MainActor
	enum BrowserWebsiteUI {
		private static var presentations: [ObjectIdentifier: UUID] = [:]

		static func javascriptDialog(
			title: String,
			message: String,
			defaultText: String? = nil,
			asksForText: Bool = false,
			confirmTitle: String = "OK",
			cancelTitle: String = "Cancel",
			in webView: WKWebView,
			isCurrent: @escaping @MainActor () -> Bool
		) async -> (confirmed: Bool, text: String?) {
			guard let window = webView.window else { return (false, nil) }
			let key = ObjectIdentifier(window)
			while presentations[key] != nil || window.rootViewController?.presentedViewController != nil {
				guard isCurrent(), !Task.isCancelled else { return (false, nil) }
				try? await Task.sleep(for: .milliseconds(100))
			}
			guard isCurrent(), let presenter = topViewController(in: window) else { return (false, nil) }
			let id = UUID()
			presentations[key] = id
			defer {
				if presentations[key] == id {
					presentations[key] = nil
				}
			}
			let alert = UIAlertController(title: title, message: String(message.prefix(4000)), preferredStyle: .alert)
			if asksForText || defaultText != nil {
				alert.addTextField { field in
					field.text = defaultText ?? ""
					field.accessibilityLabel = title
				}
			}
			return await withCheckedContinuation { continuation in
				var completed = false
				let finish: (Bool) -> Void = { confirmed in
					guard !completed else { return }
					completed = true
					continuation.resume(returning: (confirmed, confirmed ? alert.textFields?.first?.text : nil))
				}
				alert.addAction(UIAlertAction(title: confirmTitle, style: .default) { _ in finish(true) })
				alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in finish(false) })
				presenter.present(alert, animated: true)
				Task { @MainActor in
					while !completed {
						guard isCurrent(), alert.presentingViewController != nil else {
							alert.dismiss(animated: true)
							finish(false)
							return
						}
						try? await Task.sleep(for: .milliseconds(100))
					}
				}
			}
		}

		static func authenticate(
			_ challenge: URLAuthenticationChallenge,
			in webView: WKWebView,
			isCurrent: @escaping @MainActor () -> Bool
		) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
			switch BrowserAuthenticationPolicy.decision(
				method: challenge.protectionSpace.authenticationMethod,
				previousFailureCount: challenge.previousFailureCount
			) {
				case .cancel:
					return (.cancelAuthenticationChallenge, nil)
				case .useDefaultHandling:
					return (.performDefaultHandling, nil)
				case .prompt:
					break
			}
			guard let window = webView.window else { return (.cancelAuthenticationChallenge, nil) }
			let key = ObjectIdentifier(window)
			while presentations[key] != nil || window.rootViewController?.presentedViewController != nil {
				guard isCurrent(), !Task.isCancelled else { return (.cancelAuthenticationChallenge, nil) }
				try? await Task.sleep(for: .milliseconds(100))
			}
			guard isCurrent(), let presenter = topViewController(in: window) else { return (.cancelAuthenticationChallenge, nil) }
			let id = UUID()
			presentations[key] = id
			defer {
				if presentations[key] == id {
					presentations[key] = nil
				}
			}
			let encrypted = BrowserAuthenticationPolicy.isEncrypted(protocolName: challenge.protectionSpace.protocol)
			let message = encrypted
				? "This website requires a username and password."
				: "This connection is not encrypted. Your credentials may be exposed."
			let alert = UIAlertController(
				title: BrowserAuthenticationPolicy.title(
					host: challenge.protectionSpace.host,
					port: challenge.protectionSpace.port,
					realm: challenge.protectionSpace.realm
				),
				message: message,
				preferredStyle: .alert
			)
			alert.addTextField { field in
				field.placeholder = "Username"
				field.accessibilityLabel = "Username"
			}
			alert.addTextField { field in
				field.placeholder = "Password"
				field.isSecureTextEntry = true
				field.accessibilityLabel = "Password"
			}
			return await withCheckedContinuation { continuation in
				var completed = false
				let finish: (Bool) -> Void = { accepted in
					guard !completed else { return }
					completed = true
					guard accepted, isCurrent(), let fields = alert.textFields else {
						continuation.resume(returning: (.cancelAuthenticationChallenge, nil))
						return
					}
					let credential = URLCredential(
						user: fields[0].text ?? "",
						password: fields[1].text ?? "",
						persistence: .none
					)
					continuation.resume(returning: (.useCredential, credential))
				}
				alert.addAction(UIAlertAction(title: "Sign In", style: .default) { _ in finish(true) })
				alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in finish(false) })
				presenter.present(alert, animated: true)
				Task { @MainActor in
					while !completed {
						guard isCurrent(), alert.presentingViewController != nil else {
							alert.dismiss(animated: true)
							finish(false)
							return
						}
						try? await Task.sleep(for: .milliseconds(100))
					}
				}
			}
		}

		static func permissionPrompt(
			title: String,
			message: String,
			in webView: WKWebView,
			isCurrent: @escaping @MainActor () -> Bool
		) async -> BrowserSitePermissions.PromptResponse {
			guard let window = webView.window else { return .cancel }
			let key = ObjectIdentifier(window)
			while presentations[key] != nil || window.rootViewController?.presentedViewController != nil {
				guard isCurrent(), !Task.isCancelled else { return .cancel }
				try? await Task.sleep(for: .milliseconds(100))
			}
			guard isCurrent(), let presenter = topViewController(in: window) else { return .cancel }
			let id = UUID()
			presentations[key] = id
			defer {
				if presentations[key] == id {
					presentations[key] = nil
				}
			}
			return await withCheckedContinuation { continuation in
				var completed = false
				let finish: (BrowserSitePermissions.PromptResponse) -> Void = { choice in
					guard !completed else { return }
					completed = true
					continuation.resume(returning: choice)
				}
				let alert = UIAlertController(title: title, message: String(message.prefix(4000)), preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: "Allow Once", style: .default) { _ in finish(.allowOnce) })
				alert.addAction(UIAlertAction(title: "Always Allow", style: .default) { _ in finish(.allowAlways) })
				alert.addAction(UIAlertAction(title: "Don't Allow", style: .destructive) { _ in finish(.deny) })
				presenter.present(alert, animated: true)
				Task { @MainActor in
					while !completed {
						guard isCurrent(), alert.presentingViewController != nil else {
							alert.dismiss(animated: true)
							finish(.cancel)
							return
						}
						try? await Task.sleep(for: .milliseconds(100))
					}
				}
			}
		}

		private static func topViewController(in window: UIWindow) -> UIViewController? {
			var controller = window.rootViewController
			while let presented = controller?.presentedViewController {
				controller = presented
			}
			return controller
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
				_ = await BrowserWebsiteUI.javascriptDialog(
					title: frame.securityOrigin.host,
					message: message,
					in: webView
				) { [weak self, weak webView] in
					guard let self, let webView else { return false }
					return ownsPrompt(in: webView, documentID: documentID)
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
				let result = await BrowserWebsiteUI.javascriptDialog(
					title: frame.securityOrigin.host,
					message: message,
					in: webView
				) { [weak self, weak webView] in
					guard let self, let webView else { return false }
					return ownsPrompt(in: webView, documentID: documentID)
				}
				completionHandler(ownsPrompt(in: webView, documentID: documentID) && result.confirmed)
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
				let result = await BrowserWebsiteUI.javascriptDialog(
					title: frame.securityOrigin.host,
					message: prompt,
					defaultText: defaultText,
					asksForText: true,
					in: webView
				) { [weak self, weak webView] in
					guard let self, let webView else { return false }
					return ownsPrompt(in: webView, documentID: documentID)
				}
				completionHandler(ownsPrompt(in: webView, documentID: documentID) && result.confirmed ? result.text : nil)
			}
		}

		func webView(
			_ webView: WKWebView,
			didReceive challenge: URLAuthenticationChallenge,
			completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
		) {
			let documentID = navigationIdentifier
			Task { @MainActor in
				let response = await BrowserWebsiteUI.authenticate(challenge, in: webView) { [weak self, weak webView] in
					guard let self, let webView else { return false }
					return ownsPrompt(in: webView, documentID: documentID)
				}
				guard ownsPrompt(in: webView, documentID: documentID) else {
					completionHandler(.cancelAuthenticationChallenge, nil)
					return
				}
				completionHandler(response.0, response.1)
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
				decisionHandler(await requestPermission(capabilities, origin: origin, in: webView))
			}
		}

		func webView(
			_ webView: WKWebView,
			requestGeolocationPermissionFor origin: WKSecurityOrigin,
			initiatedByFrame _: WKFrameInfo,
			decisionHandler: @escaping (WKPermissionDecision) -> Void
		) {
			Task { @MainActor in
				decisionHandler(await requestPermission([.location], origin: origin, in: webView))
			}
		}

		@available(iOS 15.0, *)
		func webView(
			_ webView: WKWebView,
			requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
			initiatedByFrame _: WKFrameInfo,
			decisionHandler: @escaping (WKPermissionDecision) -> Void
		) {
			Task { @MainActor in
				decisionHandler(await requestPermission([.motion], origin: origin, in: webView))
			}
		}
	}
#endif

extension BrowserController {
	func requestPermission(
		_ capabilities: [BrowserSitePermissions.Capability],
		origin: WKSecurityOrigin,
		in webView: WKWebView
	) async -> WKPermissionDecision {
		var parts = URLComponents()
		parts.scheme = origin.protocol
		parts.host = origin.host
		parts.port = origin.port > 0 ? origin.port : nil
		guard let originURL = parts.url,
		      let topURL = committedURL ?? webView.url else { return .deny }
		return await requestPermission(capabilities, originURL: originURL, topURL: topURL, in: webView)
	}

	func requestPermission(
		_ capabilities: [BrowserSitePermissions.Capability],
		originURL: URL,
		topURL: URL,
		in webView: WKWebView
	) async -> WKPermissionDecision {
		guard let originID = BrowserSitePermissions.origin(for: originURL),
		      let topOrigin = BrowserSitePermissions.origin(for: topURL)
		else { return .deny }
		let requiresSecureOrigin = capabilities.contains { capability in
			[.camera, .microphone, .location, .motion].contains(capability)
		}
		let originHost = originURL.host?.lowercased() ?? ""
		let isLocalOrigin = originHost == "localhost"
			|| originHost.hasSuffix(".localhost")
			|| originHost == "127.0.0.1"
			|| originHost == "::1"
		let isSecureOrigin = originURL.scheme?.lowercased() == "https" || isLocalOrigin
		guard !requiresSecureOrigin || isSecureOrigin,
		      BrowserSitePermissions.origin(for: committedURL ?? webView.url ?? topURL) == topOrigin else { return .deny }
		return await requestPermission(capabilities, originID: originID, topOrigin: topOrigin, in: webView)
	}

	private func requestPermission(
		_ capabilities: [BrowserSitePermissions.Capability],
		originID: String,
		topOrigin: String,
		in webView: WKWebView
	) async -> WKPermissionDecision {
		let documentID = navigationIdentifier
		guard ownsPrompt(in: webView, documentID: documentID) else { return .deny }
		let permissions = session.permissions
		let requestRevision = permissions.revision
		guard operatingSystemAllows(capabilities) else { return .deny }
		let decisions = capabilities.map {
			permissions.effectiveDecision(
				origin: originID,
				topOrigin: topOrigin,
				capability: $0,
				controllerID: id,
				documentID: documentID
			)
		}
		if decisions.contains(.deny) { return .deny }
		if decisions.allSatisfy({ $0 == .allowOnce || $0 == .allowAlways }) { return .grant }
		let pendingCapabilities = zip(capabilities, decisions).compactMap { capability, decision in
			decision == nil ? capability : nil
		}
		let requested = pendingCapabilities.map(\.title).joined(separator: " and ").lowercased()
		let title = "Allow \(originID) to access \(requested)?"
		let message: String
		if pendingCapabilities.contains(.popups) {
			message = "Allow pop-ups, then retry the page action. This request comes from \(topOrigin)."
		} else if originID == topOrigin {
			message = "You can change this permission in Privacy and Security settings."
		} else {
			message = "This request comes from content embedded in \(topOrigin)."
		}
		let choice = await BrowserWebsiteUI.permissionPrompt(title: title, message: message, in: webView) { [weak self, weak webView] in
			guard let self, let webView else { return false }
			return ownsPrompt(in: webView, documentID: documentID) && permissions.revision == requestRevision
		}
		guard ownsPrompt(in: webView, documentID: documentID),
		      permissions.revision == requestRevision,
		      let currentTopURL = committedURL ?? webView.url,
		      BrowserSitePermissions.origin(for: currentTopURL) == topOrigin else { return .deny }
		guard let permissionDecision = BrowserSitePermissions.Decision(response: choice) else { return .deny }
		if permissionDecision == .deny {
			for capability in pendingCapabilities {
				permissions.set(.deny, origin: originID, topOrigin: topOrigin, capability: capability)
			}
			return .deny
		}
		for capability in pendingCapabilities {
			permissions.set(
				permissionDecision,
				origin: originID,
				topOrigin: topOrigin,
				capability: capability,
				controllerID: id,
				documentID: documentID
			)
		}
		return .grant
	}

	private func operatingSystemAllows(_ capabilities: [BrowserSitePermissions.Capability]) -> Bool {
		if capabilities.contains(.camera) {
			let status = AVCaptureDevice.authorizationStatus(for: .video)
			if status == .denied || status == .restricted { return false }
		}
		if capabilities.contains(.microphone) {
			let status = AVCaptureDevice.authorizationStatus(for: .audio)
			if status == .denied || status == .restricted { return false }
		}
		if capabilities.contains(.location) {
			let status = CLLocationManager().authorizationStatus
			if status == .denied || status == .restricted { return false }
		}
		return true
	}
}
