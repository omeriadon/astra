import SwiftUI
import WebKit

struct BrowserWebView {
	let controller: BrowserController

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

		func updateUIView(_ webView: WKWebView, context _: Context) {
			configure(webView)
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
		func makeNSView(context _: Context) -> WKWebView {
			let webView = controller.webView

			configure(webView)

			return webView
		}

		func updateNSView(_ webView: WKWebView, context _: Context) {
			configure(webView)
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
