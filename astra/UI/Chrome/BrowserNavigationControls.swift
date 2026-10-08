import SwiftUI
#if os(macOS)
	import AppKit
#endif

struct BrowserNavigationControls: View {
	let controller: BrowserController
	let browser: Browser

	var body: some View {
		HStack(spacing: 6) {
			#if os(macOS)
				BrowserSiteInformationButton(controller: controller)
			#endif
			NavigationBackButton(controller: controller, browser: browser)
			NavigationForwardButton(controller: controller, browser: browser)
			NavigationReloadButton(controller: controller)
			BrowserZoomControls(controller: controller)
			if controller.isReaderAvailable || controller.readerHTML != nil {
				Button(controller.readerHTML == nil ? "Show Reader" : "Hide Reader", systemImage: "doc.text") {
					controller.toggleReader()
				}
				.labelStyle(.iconOnly)
				.buttonStyle(.glass)
				.disabled(controller.isPreparingReader)
				.accessibilityLabel(controller.readerHTML == nil ? "Show Reader" : "Hide Reader")
				.accessibilityValue(controller.readerHTML == nil ? "Off" : "On")
				.accessibilityIdentifier("browser-reader-toggle")
			}
			Button("Zap Element", systemImage: "bolt.slash") {
				controller.toggleZap()
			}
			.labelStyle(.iconOnly)
			.buttonStyle(.glass)
			.tint(controller.isZapping ? .red : nil)
			.accessibilityLabel(controller.isZapping ? "Cancel Zap" : "Zap Element")
			.accessibilityIdentifier("browser-zap-element")
		}
		.buttonBorderShape(.roundedRectangle(radius: BrowserChromeMetrics.topBarButtonCornerRadius))
		.id(controller.history)
		.id(controller.historyIndex)
	}
}

private struct BrowserZoomControls: View {
	let controller: BrowserController

	var body: some View {
		HStack(spacing: 2) {
			Button("Zoom Out", systemImage: "minus.magnifyingglass") {
				controller.zoomOut()
			}
			.labelStyle(.iconOnly)
			.accessibilityIdentifier("browser-zoom-out")

			Button {
				controller.resetZoom()
			} label: {
				VStack(spacing: 0) {
					Image(systemName: "1.magnifyingglass")
					Text(controller.pageZoom, format: .percent.precision(.fractionLength(0)))
						.font(.caption2.monospacedDigit())
				}
			}
			.accessibilityLabel("Reset Zoom, currently \(Int((controller.pageZoom * 100).rounded())) percent")
			.accessibilityIdentifier("browser-zoom-reset")

			Button("Zoom In", systemImage: "plus.magnifyingglass") {
				controller.zoomIn()
			}
			.labelStyle(.iconOnly)
			.accessibilityIdentifier("browser-zoom-in")
		}
		.buttonStyle(.glass)
		.accessibilityElement(children: .contain)
		.accessibilityIdentifier("browser-zoom-controls")
	}
}

private struct NavigationIconLabel: View {
	let title: String
	let systemImage: String

	var body: some View {
		Label(title, systemImage: systemImage)
			.labelStyle(.iconOnly)
			.font(.body.scaled(by: 0.9))
			.frame(
				width: BrowserChromeMetrics.topBarButtonLabelWidth,
				height: BrowserChromeMetrics.topBarButtonLabelHeight
			)
	}
}

private struct NavigationBackButton: View {
	let controller: BrowserController
	let browser: Browser

	var body: some View {
		Button {
			#if os(macOS)
				if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
					browser.openHistoryEntry(from: controller, offset: -1)
				} else {
					controller.goBack()
				}
			#else
				controller.goBack()
			#endif
		} label: {
			NavigationIconLabel(
				title: "Back",
				systemImage: "chevron.backward"
			)
		}
		.contextMenu {
			ForEach((0 ..< controller.historyIndex).reversed(), id: \.self) { index in
				Button(
					controller.history[index].absoluteString,
					systemImage: "clock.arrow.circlepath"
				) {
					controller.go(toHistoryIndex: index)
				}
			}
		}
		.disabled(!controller.canGoBack)
		.accessibilityIdentifier("browser-back")
	}
}

private struct NavigationForwardButton: View {
	let controller: BrowserController
	let browser: Browser

	var body: some View {
		Button {
			#if os(macOS)
				if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
					browser.openHistoryEntry(from: controller, offset: 1)
				} else {
					controller.goForward()
				}
			#else
				controller.goForward()
			#endif
		} label: {
			NavigationIconLabel(
				title: "Forward",
				systemImage: "chevron.forward"
			)
		}
		.contextMenu {
			ForEach(min(controller.historyIndex + 1, controller.history.count) ..< controller.history.count, id: \.self) { index in
				Button(
					controller.history[index].absoluteString,
					systemImage: "clock.arrow.circlepath"
				) {
					controller.go(toHistoryIndex: index)
				}
			}
		}
		.disabled(!controller.canGoForward)
		.accessibilityIdentifier("browser-forward")
	}
}

private struct NavigationReloadButton: View {
	let controller: BrowserController

	var body: some View {
		Button {
			if controller.isLoading {
				controller.stopLoading()
			} else {
				controller.reload()
			}
		} label: {
			Label("Reload", systemImage: "arrow.clockwise")
				.hidden()
				.labelStyle(.iconOnly)
				.frame(
					width: BrowserChromeMetrics.topBarButtonLabelWidth,
					height: BrowserChromeMetrics.topBarButtonLabelHeight
				)
				.font(.body.scaled(by: 0.9))
		}
		.contextMenu {
			Button(
				"Force Reload",
				systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
			) {
				controller.reloadFromOrigin()
			}
		}
		.overlay {
			ZStack {
				if controller.isLoading {
					Image(systemName: "xmark")
						.transition(.blurReplace)
				} else {
					Image(systemName: "arrow.clockwise")
						.transition(.blurReplace)
				}
			}
			.animation(
				.bouncy(duration: 0.3),
				value: controller.isLoading
			)
			.allowsHitTesting(false)
		}
		.accessibilityLabel(
			controller.isLoading
				? "Stop Loading"
				: "Reload"
		)
		.accessibilityIdentifier("browser-reload")
	}
}
