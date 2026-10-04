import SwiftUI
import WebKit

struct BrowserWebView {
	let controller: BrowserController
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
		final class Coordinator {
			var insets: [EdgeInsets]?
		}

		func makeCoordinator() -> Coordinator {
			Coordinator()
		}

		func makeNSView(context: Context) -> NSView {
			let host = NSView()
			host.autoresizesSubviews = true
			mount(in: host, coordinator: context.coordinator)
			return host
		}

		func updateNSView(_ host: NSView, context: Context) {
			mount(in: host, coordinator: context.coordinator)
		}

		private func mount(in host: NSView, coordinator: Coordinator) {
			let webView = controller.webView
			if webView.superview !== host {
				webView.removeFromSuperview()
				webView.frame = host.bounds
				webView.autoresizingMask = [.width, .height]
				host.addSubview(webView)
			}
			webView.isHidden = !isVisible
			webView.setAccessibilityHidden(!isVisible)
			let insets = [obscuredInsets, minimumViewportInsets, maximumViewportInsets]
			if coordinator.insets != insets {
				configure(webView)
				coordinator.insets = insets
			}
		}

		private func configure(_ webView: WKWebView) {
			webView.obscuredContentInsets = obscuredInsets.nsInsets

			webView.setMinimumViewportInset(
				minimumViewportInsets.nsInsets,
				maximumViewportInset: maximumViewportInsets.nsInsets
			)
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
