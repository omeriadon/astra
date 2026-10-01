import SwiftUI

struct BrowserNavigationControls: View {
	let controller: BrowserController

	var body: some View {
		HStack(spacing: 6) {
			#if os(macOS)
				BrowserSiteInformationButton(controller: controller)
			#endif
			NavigationBackButton(controller: controller)
			NavigationForwardButton(controller: controller)
			NavigationReloadButton(controller: controller)
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

	var body: some View {
		Button {
			controller.goBack()
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

	var body: some View {
		Button {
			controller.goForward()
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
