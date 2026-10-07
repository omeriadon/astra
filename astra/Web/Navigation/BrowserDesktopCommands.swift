#if os(macOS)
	import AppKit
	import Darwin
	import Defaults
	import UniformTypeIdentifiers
	import WebKit

	@MainActor
	enum BrowserDesktopCommands {
		private struct ExportOwner {
			weak var browser: Browser?
			weak var controller: BrowserController?
			weak var webView: WKWebView?
			weak var window: NSWindow?
			let tabID: UUID
			let documentID: Int
			let url: URL

			func isCurrent() -> Bool {
				guard let browser, let controller, let webView, let window else { return false }
				return BrowserPageExportPolicy.ownsDocument(
					capturedGeneration: documentID,
					currentGeneration: controller.navigationIdentifier,
					capturedURL: url,
					currentURL: controller.committedURL,
					ownsWebView: browser.selectedTabID == tabID
						&& browser.selectedTab?.activeController === controller
						&& browser.session === controller.session
						&& controller.webViewIfLoaded === webView
						&& controller.hasCurrentPageDocument,
					ownsWindow: webView.window === window,
					isCommitted: controller.committedURL != nil,
					isLoading: controller.isLoading
				)
			}
		}

		enum ExportFormat {
			case pdf
			case webArchive
			case source
		}

		static func configureWebInspector(_ webView: WKWebView, enabled: Bool) {
			webView.isInspectable = enabled
			let preferences = webView.configuration.preferences
			if preferences.responds(to: NSSelectorFromString("_setDeveloperExtrasEnabled:")) {
				preferences.setValue(enabled, forKey: "developerExtrasEnabled")
			}
			if !enabled,
			   webView.responds(to: NSSelectorFromString("_inspector")),
			   let inspector = webView.perform(NSSelectorFromString("_inspector"))?.takeUnretainedValue() as? NSObject,
			   inspector.responds(to: NSSelectorFromString("close"))
			{
				inspector.perform(NSSelectorFromString("close"))
			}
		}

		static func showWebInspector(_ controller: BrowserController, selectingElement: Bool = false) {
			guard let webView = controller.webViewIfLoaded,
			      controller.hasCurrentPageDocument else { return }
			// Persist docking preferences only when opening, outside the defaults observer path.
			UserDefaults.standard.set(1, forKey: "__WebInspectorPageGroupLevel1__.WebKit2InspectorAttachmentSide")
			UserDefaults.standard.set(true, forKey: "__WebInspectorPageGroupLevel1__.WebKit2InspectorStartsAttached")
			Defaults[.webInspectorEnabled] = true
			configureWebInspector(webView, enabled: true)
			guard webView.responds(to: NSSelectorFromString("_inspector")),
			      let inspector = webView.perform(NSSelectorFromString("_inspector"))?.takeUnretainedValue() as? NSObject,
			      inspector.responds(to: NSSelectorFromString("show")),
			      inspector.responds(to: NSSelectorFromString("close")),
			      inspector.responds(to: NSSelectorFromString("attach"))
			else {
				controller.session.toastManager.show(
					symbol: "exclamationmark.triangle",
					message: "This WebKit version cannot open Astra’s Web Inspector. Inspect this page from Safari’s Develop menu."
				)
				return
			}
			if selectingElement {
				guard inspector.responds(to: NSSelectorFromString("toggleElementSelection")) else {
					controller.session.toastManager.show(symbol: "exclamationmark.triangle", message: "Element selection is unavailable in this WebKit version.")
					return
				}
				if inspector.value(forKey: "isElementSelectionActive") as? Bool != true {
					// Connect without showing the inspector until an element has been selected.
					inspector.perform(NSSelectorFromString("toggleElementSelection"))
				}
			} else {
				let isVisible = inspector.value(forKey: "isVisible") as? Bool == true
				inspector.perform(NSSelectorFromString(isVisible ? "close" : "show"))
			}
		}

		static func attachWebInspector(_ inspector: NSObject) {
			// The C entry point preserves the configured side; Objective-C attach defaults to bottom.
			guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "WKInspectorAttach") else { return }
			let attach = unsafeBitCast(symbol, to: (@convention(c) (UnsafeRawPointer) -> Void).self)
			attach(UnsafeRawPointer(Unmanaged.passUnretained(inspector).toOpaque()))
		}

		static func openFile(in browser: Browser, window: NSWindow?) {
			guard let window else { return }
			let panel = NSOpenPanel()
			panel.allowedContentTypes = [.html, .pdf, .image, .plainText, UTType(filenameExtension: "webarchive") ?? .data]
			panel.allowsMultipleSelection = true
			panel.beginSheetModal(for: window) { response in
				guard response == .OK else { return }
				for url in panel.urls {
					let tab = browser.addTab()
					tab.controller?.loadLocalFile(url)
				}
			}
		}

		static func printPage(_ controller: BrowserController, window: NSWindow?) {
			guard let webView = controller.webViewIfLoaded,
			      controller.hasCurrentPageDocument,
			      !controller.isLoading,
			      let window,
			      webView.window === window
			else { return }
			let operation = webView.printOperation(with: .shared)
			operation.showsPrintPanel = true
			operation.showsProgressPanel = true
			operation.runModal(
				for: window,
				delegate: nil,
				didRun: nil,
				contextInfo: nil
			)
		}

		static func export(
			_ controller: BrowserController,
			in browser: Browser,
			format: ExportFormat,
			window: NSWindow?
		) {
			guard let webView = controller.webViewIfLoaded,
			      browser.selectedTab?.activeController === controller,
			      let window,
			      let url = controller.committedURL,
			      !controller.isLoading
			else { return }
			let owner = ExportOwner(
				browser: browser,
				controller: controller,
				webView: webView,
				window: window,
				tabID: browser.selectedTabID,
				documentID: controller.navigationIdentifier,
				url: url
			)
			guard owner.isCurrent() else { return }
			let title = BrowserDownloadManager.safeStem(webView.title ?? "Page")

			if format == .source {
				Task { @MainActor in
					do {
						let source = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String ?? ""
						guard owner.isCurrent(), !Task.isCancelled else { return }
						guard BrowserSourceDocumentPolicy.accepts(source) else {
							controller.session.toastManager.show(
								symbol: "exclamationmark.triangle",
								message: "Source is empty or larger than 5 MB and cannot be displayed safely."
							)
							return
						}
						BrowserSourceViewer.show(source: source, title: title, sourceURL: url)
					} catch {
						guard owner.isCurrent() else { return }
						controller.session.toastManager.show(symbol: "exclamationmark.triangle", message: "Could not read source: \(error.localizedDescription)")
					}
				}
				return
			}

			let panel = NSSavePanel()
			switch format {
				case .pdf:
					panel.allowedContentTypes = [.pdf]
					panel.nameFieldStringValue = title + ".pdf"
				case .webArchive:
					panel.allowedContentTypes = [UTType(filenameExtension: "webarchive") ?? .data]
					panel.nameFieldStringValue = title + ".webarchive"
				case .source:
					return
			}
			panel.beginSheetModal(for: window) { response in
				guard response == .OK, let destination = panel.url else { return }
				Task { @MainActor in
					defer { destination.stopAccessingSecurityScopedResource() }
					guard owner.isCurrent() else { return }
					var createdDestination = false
					do {
						let data: Data
						switch format {
							case .pdf:
								data = try await webView.pdf(configuration: WKPDFConfiguration())
							case .webArchive:
								data = try await withCheckedThrowingContinuation { continuation in
									webView.createWebArchiveData { result in
										continuation.resume(with: result)
									}
								}
							case .source:
								return
						}
						guard owner.isCurrent(), !Task.isCancelled else { return }
						try BrowserPageExportPolicy.writeExclusively(data, to: destination)
						createdDestination = true
						let attributionURL = BrowserAddress.withoutCredentials(url)
						try BrowserDownloadedFile.quarantine(destination, downloadURL: attributionURL, sourceURL: attributionURL)
					} catch {
						if createdDestination {
							try? FileManager.default.removeItem(at: destination)
						}
						guard owner.isCurrent() else { return }
						controller.session.toastManager.show(symbol: "exclamationmark.triangle", message: "Could not save page: \(error.localizedDescription)")
					}
				}
			}
		}

		static func sharePage(_ controller: BrowserController, in browser: Browser, window: NSWindow?) {
			guard let webView = controller.webViewIfLoaded,
			      browser.selectedTab?.activeController === controller,
			      let window,
			      let url = controller.committedURL,
			      controller.hasCurrentPageDocument,
			      !controller.isLoading
			else { return }
			let owner = ExportOwner(
				browser: browser,
				controller: controller,
				webView: webView,
				window: window,
				tabID: browser.selectedTabID,
				documentID: controller.navigationIdentifier,
				url: url
			)
			guard owner.isCurrent() else { return }
			let shareURL = BrowserAddress.withoutCredentials(url)
			let title = webView.title ?? shareURL.absoluteString
			Task { @MainActor in
				let selectedText = try? await webView.evaluateJavaScript("window.getSelection().toString()") as? String
				guard owner.isCurrent() else { return }
				let items: [Any] = selectedText.flatMap { $0.isEmpty ? nil : $0 }.map { [$0, shareURL] } ?? [title, shareURL]
				NSSharingServicePicker(items: items).show(
					relativeTo: webView.bounds,
					of: webView,
					preferredEdge: .minY
				)
			}
		}
	}
#endif
