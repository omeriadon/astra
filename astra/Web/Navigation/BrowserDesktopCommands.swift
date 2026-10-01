#if os(macOS)
	import AppKit
	import UniformTypeIdentifiers
	import WebKit

	@MainActor
	enum BrowserDesktopCommands {
		enum ExportFormat {
			case pdf
			case webArchive
			case source
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
			guard let webView = controller.webViewIfLoaded, let window else { return }
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
			format: ExportFormat,
			window: NSWindow?
		) {
			guard let webView = controller.webViewIfLoaded, let window else { return }
			let panel = NSSavePanel()
			let title = BrowserDownloadManager.safeStem(webView.title ?? "Page")
			switch format {
				case .pdf:
					panel.allowedContentTypes = [.pdf]
					panel.nameFieldStringValue = title + ".pdf"
				case .webArchive:
					panel.allowedContentTypes = [UTType(filenameExtension: "webarchive") ?? .data]
					panel.nameFieldStringValue = title + ".webarchive"
				case .source:
					panel.allowedContentTypes = [.html]
					panel.nameFieldStringValue = title + ".html"
			}
			panel.beginSheetModal(for: window) { response in
				guard response == .OK, let destination = panel.url else { return }
				Task { @MainActor in
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
								let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String ?? ""
								data = Data(html.utf8)
						}
						let access = destination.startAccessingSecurityScopedResource()
						defer {
							if access {
								destination.stopAccessingSecurityScopedResource()
							}
						}
						try data.write(to: destination, options: .atomic)
						try BrowserDownloadedFile.quarantine(destination, downloadURL: webView.url, sourceURL: webView.url)
					} catch {
						ToastManager.shared.show(symbol: "exclamationmark.triangle", message: "Could not save page: \(error.localizedDescription)")
					}
				}
			}
		}
	}
#endif
