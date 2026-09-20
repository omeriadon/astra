//
//  BrowserWebView.swift
//  browser
//
//  Created by Adon Omeri on 20/9/2026.
//

import SwiftUI
import WebKit
import Observation


@MainActor
@Observable
final class BrowserController: NSObject {

	@ObservationIgnored
	let webView = WKWebView()

	var canGoBack = false
	var canGoForward = false

	@ObservationIgnored
	private var observations: [NSKeyValueObservation] = []

	override init() {
		super.init()

		observations = [
			webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
				Task { @MainActor in
					self?.canGoBack = webView.canGoBack
				}
			},

			webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
				Task { @MainActor in
					self?.canGoForward = webView.canGoForward
				}
			}
		]
	}

	func goBack() {
		webView.goBack()
	}

	func goForward() {
		webView.goForward()
	}

	func reload() {
		webView.reload()
	}
}


struct BrowserWebView {

	let url: URL
	let controller: BrowserController

	/// UI currently covering the webpage.
	var obscuredInsets = EdgeInsets()

	/// Insets when your browser UI is maximally collapsed.
	var minimumViewportInsets = EdgeInsets()

	/// Insets when your browser UI is maximally expanded.
	var maximumViewportInsets = EdgeInsets()

	final class Coordinator {
		var loadedURL: URL?
	}

	func makeCoordinator() -> Coordinator {
		Coordinator()
	}
}


#if os(iOS)

extension BrowserWebView: UIViewRepresentable {

	func makeUIView(context: Context) -> WKWebView {
		let webView = controller.webView

		configure(webView)

		context.coordinator.loadedURL = url
		webView.load(URLRequest(url: url))

		return webView
	}

	func updateUIView(_ webView: WKWebView, context: Context) {
		configure(webView)

		if context.coordinator.loadedURL != url {
			context.coordinator.loadedURL = url
			webView.load(URLRequest(url: url))
		}
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

	func makeNSView(context: Context) -> WKWebView {
		let webView = controller.webView

		configure(webView)

		context.coordinator.loadedURL = url
		webView.load(URLRequest(url: url))

		return webView
	}

	func updateNSView(_ webView: WKWebView, context: Context) {
		configure(webView)

		if context.coordinator.loadedURL != url {
			context.coordinator.loadedURL = url
			webView.load(URLRequest(url: url))
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
