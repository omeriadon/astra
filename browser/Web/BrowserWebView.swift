import SwiftUI
import WebKit

struct BrowserWebView {
	let controller: BrowserController
	var cornerRadius: CGFloat = 0

	/// UI currently covering the webpage.
	var obscuredInsets = EdgeInsets()

	/// Insets when your browser UI is maximally collapsed.
	var minimumViewportInsets = EdgeInsets()

	/// Insets when your browser UI is maximally expanded.
	var maximumViewportInsets = EdgeInsets()
}

#if os(iOS)

	extension BrowserWebView: UIViewRepresentable {
		func makeUIView(context _: Context) -> UIView {
			let webView = controller.webView
			configure(webView)
			let container = UIView()
			container.layer.cornerRadius = cornerRadius
			container.layer.cornerCurve = .continuous
			container.layer.masksToBounds = true
			webView.removeFromSuperview()
			webView.translatesAutoresizingMaskIntoConstraints = false
			container.addSubview(webView)
			NSLayoutConstraint.activate([
				webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
				webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
				webView.topAnchor.constraint(equalTo: container.topAnchor),
				webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
			])
			return container
		}

		func updateUIView(_ view: UIView, context _: Context) {
			view.layer.cornerRadius = cornerRadius
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
		func makeNSView(context _: Context) -> NSView {
			let webView = controller.webView
			configure(webView)
			let container = NSView()
			container.wantsLayer = true
			container.layer?.cornerRadius = cornerRadius
			container.layer?.cornerCurve = .continuous
			container.layer?.masksToBounds = true
			webView.removeFromSuperview()
			webView.translatesAutoresizingMaskIntoConstraints = false
			container.addSubview(webView)
			NSLayoutConstraint.activate([
				webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
				webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
				webView.topAnchor.constraint(equalTo: container.topAnchor),
				webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
			])
			return container
		}

		func updateNSView(_ view: NSView, context _: Context) {
			view.layer?.cornerRadius = cornerRadius
			configure(controller.webView)
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
