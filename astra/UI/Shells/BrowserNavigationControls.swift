import SwiftUI

struct BrowserNavigationControls: View {
	let controller: BrowserController

	private func navigationLabel(
		_ title: String,
		systemImage: String
	) -> some View {
		Label(title, systemImage: systemImage)
			.labelStyle(.iconOnly)
			.font(.body.scaled(by: 0.9))
			.frame(
				width: BrowserChromeMetrics.topBarButtonLabelWidth,
				height: BrowserChromeMetrics.topBarButtonLabelHeight
			)
	}

	var body: some View {
		HStack(spacing: 6) {
			Button {
				controller.goBack()
			} label: {
				navigationLabel(
					"Back",
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

			Button {
				controller.goForward()
			} label: {
				navigationLabel(
					"Forward",
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
		.buttonBorderShape(.roundedRectangle(radius: BrowserChromeMetrics.topBarButtonCornerRadius))
		.id(controller.history)
		.id(controller.historyIndex)
	}
}
