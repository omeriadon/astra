import SwiftUI
import WebKit

struct BrowserWebView {
	let controller: BrowserController
	var windowID: UUID?
	var isVisible = true

	/// UI currently covering the webpage.
	var obscuredInsets = EdgeInsets()

	/// Insets when your browser UI is maximally collapsed.
	var minimumViewportInsets = EdgeInsets()

	/// Insets when your browser UI is maximally expanded.
	var maximumViewportInsets = EdgeInsets()
}

#if os(iOS)

	extension BrowserWebView: UIViewRepresentable {
		func makeUIView(context _: Context) -> WKWebView {
			let webView = controller.webView
			configure(webView)
			return webView
		}

		func updateUIView(_: WKWebView, context _: Context) {
			configure(controller.webView)
		}

		private func configure(_ webView: WKWebView) {
			webView.obscuredContentInsets = obscuredInsets.uiInsets

			webView.setMinimumViewportInset(
				minimumViewportInsets.uiInsets,
				maximumViewportInset: maximumViewportInsets.uiInsets
			)
		}
	}

	private extension EdgeInsets {
		var uiInsets: UIEdgeInsets {
			UIEdgeInsets(
				top: top,
				left: leading,
				bottom: bottom,
				right: trailing
			)
		}
	}

#elseif os(macOS)

	extension BrowserWebView: NSViewRepresentable {
		func makeNSView(context _: Context) -> BrowserWebViewHost {
			BrowserWebViewHost(specification: self)
		}

		func updateNSView(_ host: BrowserWebViewHost, context _: Context) {
			host.specification = self
			host.mountIfReady()
		}

		static func dismantleNSView(_ host: BrowserWebViewHost, coordinator _: ()) {
			host.handoffTask?.cancel()
		}
	}

	final class BrowserWebViewHost: NSView {
		var specification: BrowserWebView
		var handoffTask: Task<Void, Never>?
		private let curtain = NSImageView()
		private var insets: [EdgeInsets]?

		init(specification: BrowserWebView) {
			self.specification = specification
			super.init(frame: .zero)
			curtain.imageScaling = .scaleProportionallyUpOrDown
			curtain.autoresizingMask = [.width, .height]
			curtain.setAccessibilityHidden(true)
			addSubview(curtain)
		}

		@available(*, unavailable)
		required init?(coder _: NSCoder) {
			fatalError("init(coder:) is unavailable")
		}

		override func layout() {
			super.layout()
			mountIfReady()
		}

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			mountIfReady()
		}

		func mountIfReady() {
			guard window != nil, !bounds.isEmpty,
			      specification.windowID == nil || specification.controller.displayWindowID == specification.windowID else { return }
			let controller = specification.controller
			let webView = controller.webView
			if webView.superview !== self {
				handoffTask?.cancel()
				curtain.frame = bounds
				curtain.image = controller.windowMirrorSnapshot ?? controller.previewSnapshot
				curtain.isHidden = !specification.isVisible || curtain.image == nil
				webView.removeFromSuperview()
				webView.frame = bounds
				webView.autoresizingMask = [.width, .height]
				addSubview(webView, positioned: .below, relativeTo: curtain)
				handoffTask = Task { @MainActor [weak self, weak webView] in
					let deadline = ContinuousClock.now + .seconds(1)
					while !Task.isCancelled, ContinuousClock.now < deadline {
						if await controller.refreshWindowMirrorSnapshot() {
							break
						}
						do {
							try await Task.sleep(for: .milliseconds(20))
						} catch {
							return
						}
					}
					guard !Task.isCancelled, let self, let webView, webView.superview === self,
					      specification.windowID == nil || specification.windowID == controller.displayWindowID else { return }
					curtain.isHidden = true
				}
			}
			webView.isHidden = !specification.isVisible
			webView.setAccessibilityHidden(!specification.isVisible)
			let nextInsets = [specification.obscuredInsets, specification.minimumViewportInsets, specification.maximumViewportInsets]
			if insets != nextInsets {
				webView.obscuredContentInsets = specification.obscuredInsets.nsInsets
				webView.setMinimumViewportInset(specification.minimumViewportInsets.nsInsets, maximumViewportInset: specification.maximumViewportInsets.nsInsets)
				insets = nextInsets
			}
		}
	}

	private extension EdgeInsets {
		var nsInsets: NSEdgeInsets {
			NSEdgeInsets(
				top: top,
				left: leading,
				bottom: bottom,
				right: trailing
			)
		}
	}

#endif
