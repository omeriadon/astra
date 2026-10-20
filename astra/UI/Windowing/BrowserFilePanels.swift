import SwiftUI
import UniformTypeIdentifiers

extension View {
	/// Native split panes have independent hosting roots. Anchor file panels to
	/// the containing AppKit window rather than SwiftUI's scene presenter.
	func browserFileImporter(
		isPresented: Binding<Bool>,
		allowedContentTypes: [UTType],
		allowsMultipleSelection: Bool,
		onCompletion: @escaping (Result<[URL], Error>) -> Void
	) -> some View {
		#if os(macOS)
			background {
				BrowserFileImporter(isPresented: isPresented, allowedContentTypes: allowedContentTypes,
				                    allowsMultipleSelection: allowsMultipleSelection, onCompletion: onCompletion)
			}
		#else
			fileImporter(isPresented: isPresented, allowedContentTypes: allowedContentTypes,
			             allowsMultipleSelection: allowsMultipleSelection, onCompletion: onCompletion)
		#endif
	}

	func browserFileImporter(
		isPresented: Binding<Bool>,
		allowedContentTypes: [UTType],
		onCompletion: @escaping (Result<URL, Error>) -> Void
	) -> some View {
		browserFileImporter(isPresented: isPresented, allowedContentTypes: allowedContentTypes,
		                    allowsMultipleSelection: false) { result in
			onCompletion(result.flatMap { urls in
				guard let url = urls.first else { return .failure(CocoaError(.fileReadUnknown)) }
				return .success(url)
			})
		}
	}
}

#if os(macOS)
	import AppKit

	@MainActor
	enum BrowserFilePanels {
		/// Retain the panel until completion and wait for any existing sheet to
		/// finish. Never look up NSApp.keyWindow: the panel itself can become key.
		@discardableResult
		static func present(
			_ panel: NSSavePanel,
			in window: NSWindow,
			completionHandler: @escaping (NSApplication.ModalResponse) -> Void
		) -> Task<Void, Never> {
			Task { @MainActor in
				// Avoid starting a sheet during an NSViewRepresentable update.
				await Task.yield()
				while window.attachedSheet != nil {
					guard !Task.isCancelled, window.isVisible else {
						completionHandler(.cancel)
						return
					}
					do { try await Task.sleep(for: .milliseconds(100)) }
					catch { completionHandler(.cancel); return }
				}
				guard !Task.isCancelled, window.isVisible else {
					completionHandler(.cancel)
					return
				}
				let response = await withCheckedContinuation { continuation in
					panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
				}
				completionHandler(response)
			}
		}
	}

	@MainActor
	private struct BrowserFileImporter: NSViewRepresentable {
		@Binding var isPresented: Bool
		let allowedContentTypes: [UTType]
		let allowsMultipleSelection: Bool
		let onCompletion: (Result<[URL], Error>) -> Void

		func makeCoordinator() -> Coordinator { Coordinator() }
		func makeNSView(context _: Context) -> AnchorView { AnchorView(frame: .zero) }

		func updateNSView(_ view: AnchorView, context: Context) {
			let coordinator = context.coordinator
			view.onWindow = { [weak view, weak coordinator] in
				guard let view, let coordinator else { return }
				updatePresentation(view, coordinator: coordinator)
			}
			updatePresentation(view, coordinator: coordinator)
		}

		private func updatePresentation(_ view: NSView, coordinator: Coordinator) {
			guard isPresented else {
				coordinator.cancel()
				return
			}
			guard coordinator.panel == nil, let window = unsafe view.window else { return }
			let panel = NSOpenPanel()
			panel.allowedContentTypes = allowedContentTypes
			panel.canChooseDirectories = allowedContentTypes.contains(.folder)
			panel.canChooseFiles = !panel.canChooseDirectories
			panel.allowsMultipleSelection = allowsMultipleSelection
			coordinator.panel = panel
			coordinator.presentation = BrowserFilePanels.present(panel, in: window) { [weak coordinator] response in
				guard let coordinator, coordinator.panel === panel else { return }
				let urls = panel.urls
				coordinator.panel = nil
				coordinator.presentation = nil
				isPresented = false
				// Cancellation is an ordinary dismissal, not an import error.
				if response == .OK { onCompletion(.success(urls)) }
			}
		}

		static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
			view.onWindow = nil
			coordinator.cancel()
		}

		final class AnchorView: NSView {
			var onWindow: (() -> Void)?
			override func hitTest(_: NSPoint) -> NSView? { nil }
			override func viewDidMoveToWindow() {
				super.viewDidMoveToWindow()
				onWindow?()
			}
		}

		@MainActor
		final class Coordinator {
			var panel: NSOpenPanel?
			var presentation: Task<Void, Never>?

			func cancel() {
				let current = panel
				panel = nil
				presentation?.cancel()
				presentation = nil
				current?.cancel(nil)
			}
		}
	}
#endif
