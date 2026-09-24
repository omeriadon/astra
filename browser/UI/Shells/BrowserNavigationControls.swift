import SwiftUI

struct BrowserNavigationControls: View {
	let controller: BrowserController

	private func navigationLabel(
		_ title: String,
		systemImage: String
	) -> some View {
		Label(title, systemImage: systemImage)
			.labelStyle(.iconOnly)
			.frame(
				width: BrowserChromeMetrics.topBarButtonLabelWidth,
				height: BrowserChromeMetrics.topBarButtonLabelHeight
			)
	}

	var body: some View {
		HStack(spacing: 6) {
			Menu {
				if controller.canGoBack {
					ForEach((0 ..< controller.historyIndex).reversed(), id: \.self) { index in
						Button(
							controller.history[index].absoluteString,
							systemImage: "clock.arrow.circlepath"
						) {
							controller.go(toHistoryIndex: index)
						}
					}
				}
			} label: {
				navigationLabel(
					"Back",
					systemImage: "chevron.backward"
				)
			} primaryAction: {
				controller.goBack()
			}
			.disabled(!controller.canGoBack)
			.accessibilityIdentifier("browser-back")

			Menu {
				if controller.canGoForward {
					ForEach((controller.historyIndex + 1) ..< controller.history.count, id: \.self) { index in
						Button(
							controller.history[index].absoluteString,
							systemImage: "clock.arrow.circlepath"
						) {
							controller.go(toHistoryIndex: index)
						}
					}
				}
			} label: {
				navigationLabel(
					"Forward",
					systemImage: "chevron.forward"
				)
			} primaryAction: {
				controller.goForward()
			}
			.disabled(!controller.canGoForward)
			.accessibilityIdentifier("browser-forward")

			Menu {
				Button(
					"Force Reload",
					systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
				) {
					controller.reloadFromOrigin()
				}
			} label: {
				Label("Reload", systemImage: "arrow.clockwise")
					.hidden()
					.labelStyle(.iconOnly)
					.frame(
						width: BrowserChromeMetrics.topBarButtonLabelWidth,
						height: BrowserChromeMetrics.topBarButtonLabelHeight
					)
			} primaryAction: {
				if controller.isLoading {
					controller.stopLoading()
				} else {
					controller.reload()
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
		.menuIndicator(.hidden)
		.buttonBorderShape(.roundedRectangle(radius: BrowserChromeMetrics.topBarButtonCornerRadius))
		.id(controller.history)
		.id(controller.historyIndex)
	}
}
