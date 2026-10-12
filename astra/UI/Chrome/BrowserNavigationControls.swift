import SwiftUI
#if os(macOS)
	import AppKit
#endif

/// Use exactly the same control metrics and styling as Back, Forward and Reload.
struct AstraTopBarButtonModifier: ViewModifier {
	func body(content: Content) -> some View {
		content
			.controlSize(.regular)
			.labelStyle(.iconOnly)
			.buttonSizing(.fitted)
			.buttonStyle(.bordered)
			.foregroundStyle(.primary)
			.buttonBorderShape(.roundedRectangle(radius: BrowserChromeMetrics.topBarButtonCornerRadius))
	}
}

extension View {
	func astraTopBarButton() -> some View {
		modifier(AstraTopBarButtonModifier())
	}
}

struct AstraTopBarIcon: View {
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

struct BrowserNavigationControls: View {
	let controller: BrowserController
	let browser: Browser

	var body: some View {
		HStack(spacing: 6) {
			BrowserHistoryNavigationControls(controller: controller, browser: browser)
			BrowserZoomControls(controller: controller)
			if controller.isReaderAvailable || controller.readerHTML != nil {
				Button {
					controller.toggleReader()
				} label: {
					AstraTopBarIcon(title: controller.readerHTML == nil ? "Show Reader" : "Hide Reader", systemImage: "doc.text")
				}
				.astraTopBarButton()
				.disabled(controller.isPreparingReader)
				.accessibilityLabel(controller.readerHTML == nil ? "Show Reader" : "Hide Reader")
				.accessibilityValue(controller.readerHTML == nil ? "Off" : "On")
				.accessibilityIdentifier("browser-reader-toggle")
			}
			#if os(iOS)
				Button {
					controller.toggleZap()
				} label: {
					AstraTopBarIcon(title: "Zap Element", systemImage: "bolt.slash")
				}
				.astraTopBarButton()
				.tint(controller.isZapping ? .red : nil)
				.accessibilityLabel(controller.isZapping ? "Cancel Zap" : "Zap Element")
				.accessibilityIdentifier("browser-zap-element")
			#endif
		}
		.buttonBorderShape(.roundedRectangle(radius: BrowserChromeMetrics.topBarButtonCornerRadius))
		.id(controller.history)
		.id(controller.historyIndex)
	}
}

struct BrowserHistoryNavigationControls: View {
	let controller: BrowserController
	let browser: Browser
	var separatesReload = false

	var body: some View {
		HStack(spacing: 6) {
			NavigationBackButton(controller: controller, browser: browser)
			NavigationForwardButton(controller: controller, browser: browser)
			Color.clear.frame(width: BrowserChromeMetrics.historyGroupSpacerWidth, height: 1)
			if separatesReload {
				Spacer(minLength: 0)
			}
			NavigationReloadButton(controller: controller)
			if !separatesReload {
				Color.clear.frame(width: BrowserChromeMetrics.historyGroupSpacerWidth, height: 1)
			}
		}
		.controlSize(.regular)
		.labelStyle(.iconOnly)
		.buttonSizing(.fitted)
		.buttonStyle(.bordered)
		.foregroundStyle(.primary)
		.buttonBorderShape(.roundedRectangle(radius: BrowserChromeMetrics.topBarButtonCornerRadius))
		.id(controller.history)
		.id(controller.historyIndex)
	}
}

private struct BrowserZoomControls: View {
	let controller: BrowserController
	@State private var showsZoom = false

	var body: some View {
		Button {
			showsZoom.toggle()
		} label: {
			AstraTopBarIcon(title: "Page Zoom", systemImage: "magnifyingglass")
		}
		.astraTopBarButton()
		.accessibilityLabel("Page Zoom, \(Int((controller.pageZoom * 100).rounded())) percent")
		.accessibilityIdentifier("browser-zoom-controls")
		.popover(isPresented: $showsZoom, arrowEdge: .top) {
			HStack(spacing: 12) {
				Button("Zoom Out", systemImage: "minus") { controller.zoomOut() }
					.labelStyle(.iconOnly)
					.disabled(controller.pageZoom <= BrowserZoomPolicy.range.lowerBound)
					.accessibilityIdentifier("browser-zoom-out")
				Button {
					controller.resetZoom()
				} label: {
					Text(controller.pageZoom, format: .percent.precision(.fractionLength(0)))
						.monospacedDigit()
						.frame(minWidth: 52)
				}
				.accessibilityLabel("Reset page zoom")
				.accessibilityIdentifier("browser-zoom-reset")
				Button("Zoom In", systemImage: "plus") { controller.zoomIn() }
					.labelStyle(.iconOnly)
					.disabled(controller.pageZoom >= BrowserZoomPolicy.range.upperBound)
					.accessibilityIdentifier("browser-zoom-in")
			}
			.buttonStyle(.bordered)
			.padding(12)
			.accessibilityElement(children: .contain)
		}
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
	@State private var showsHistory = false

	private var historyEntries: some View {
		ForEach((0 ..< controller.historyIndex).reversed(), id: \.self) { index in
			Button(controller.history[index].absoluteString, systemImage: "clock.arrow.circlepath") {
				controller.go(toHistoryIndex: index)
			}
		}
	}

	private func navigate() {
		#if os(macOS)
			if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
				browser.openHistoryEntry(from: controller, offset: -1)
			} else {
				controller.goBack()
			}
		#else
			controller.goBack()
		#endif
	}

	var body: some View {
		Button {
			navigate()
		} label: {
			NavigationIconLabel(title: "Back", systemImage: "chevron.backward")
		}
		.astraTopBarButton()
		.overlay {
			// Native bordered buttons consume mouse tracking before SwiftUI hold gestures.
			Color.clear
				.contentShape(Rectangle())
				.gesture(
					LongPressGesture(minimumDuration: 0.45)
						.exclusively(before: TapGesture())
						.onEnded { gesture in
							switch gesture {
								case .first:
									showsHistory = true
								case .second:
									navigate()
							}
						}
				)
				.allowsHitTesting(controller.canGoBack)
				.accessibilityHidden(true)
		}
		.contextMenu { historyEntries }
		.popover(isPresented: $showsHistory, arrowEdge: .top) {
			VStack(alignment: .leading, spacing: 6) {
				historyEntries
			}
			.padding(8)
		}
		.disabled(!controller.canGoBack)
		.accessibilityIdentifier("browser-back")
		.accessibilityLabel("Back")
	}
}

private struct NavigationForwardButton: View {
	let controller: BrowserController
	let browser: Browser
	@State private var showsHistory = false

	private var historyEntries: some View {
		ForEach(min(controller.historyIndex + 1, controller.history.count) ..< controller.history.count, id: \.self) { index in
			Button(controller.history[index].absoluteString, systemImage: "clock.arrow.circlepath") {
				controller.go(toHistoryIndex: index)
			}
		}
	}

	private func navigate() {
		#if os(macOS)
			if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
				browser.openHistoryEntry(from: controller, offset: 1)
			} else {
				controller.goForward()
			}
		#else
			controller.goForward()
		#endif
	}

	var body: some View {
		Button {
			navigate()
		} label: {
			NavigationIconLabel(title: "Forward", systemImage: "chevron.forward")
		}
		.astraTopBarButton()
		.overlay {
			// Native bordered buttons consume mouse tracking before SwiftUI hold gestures.
			Color.clear
				.contentShape(Rectangle())
				.gesture(
					LongPressGesture(minimumDuration: 0.45)
						.exclusively(before: TapGesture())
						.onEnded { gesture in
							switch gesture {
								case .first:
									showsHistory = true
								case .second:
									navigate()
							}
						}
				)
				.allowsHitTesting(controller.canGoForward)
				.accessibilityHidden(true)
		}
		.contextMenu { historyEntries }
		.popover(isPresented: $showsHistory, arrowEdge: .top) {
			VStack(alignment: .leading, spacing: 6) {
				historyEntries
			}
			.padding(8)
		}
		.disabled(!controller.canGoForward)
		.accessibilityIdentifier("browser-forward")
		.accessibilityLabel("Forward")
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
