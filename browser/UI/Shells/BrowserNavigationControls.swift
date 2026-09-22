import SwiftUI
import WebKit

struct BrowserNavigationControls: View {
	let controller: BrowserController?
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private var backItems: [WKBackForwardListItem] {
		controller?.backHistoryItems ?? []
	}

	private var forwardItems: [WKBackForwardListItem] {
		controller?.forwardHistoryItems ?? []
	}

	var body: some View {
		HStack(spacing: 6) {
			Menu {
				if backItems.isEmpty {
					Button("No Back History", systemImage: "minus.circle") {}
						.disabled(true)
				} else {
					ForEach(backItems.enumerated(), id: \.offset) { _, item in
						Button(item.title ?? item.url.absoluteString, systemImage: "clock.arrow.circlepath") {
							controller?.go(to: item)
						}
					}
				}
			} label: {
				Label("Back", systemImage: "chevron.backward")
					.labelStyle(.iconOnly)
					.frame(width: topBarItemWidth, height: topBarItemHeight)
					.foregroundStyle(controller?.canGoBack == true ? .primary : .tertiary)
					.clipShape(.rect(cornerRadius: 8))

			} primaryAction: {
				controller?.goBack()
			}
			.clipShape(.rect(cornerRadius: 8))
			.accessibilityIdentifier("browser-back")

			Menu {
				if forwardItems.isEmpty {
					Button("No Forward History", systemImage: "minus.circle") {}
						.disabled(true)
				} else {
					ForEach(forwardItems.enumerated(), id: \.offset) { _, item in
						Button(item.title ?? item.url.absoluteString, systemImage: "clock.arrow.circlepath") {
							controller?.go(to: item)
						}
					}
				}
			} label: {
				Label("Forward", systemImage: "chevron.forward")
					.labelStyle(.iconOnly)
					.frame(width: topBarItemWidth, height: topBarItemHeight)
					.foregroundStyle(controller?.canGoForward == true ? .primary : .tertiary)
			} primaryAction: {
				controller?.goForward()
			}
			.clipShape(.rect(cornerRadius: 8))
			.accessibilityIdentifier("browser-forward")

			Menu {
				Button("Force Reload", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
					controller?.reloadFromOrigin()
				}

			} label: {
				Label {
					Text(controller?.isLoading == true ? "Stop Loading" : "Reload")
				} icon: {
					if controller?.isLoading == true {
						if reduceMotion {
							Image(systemName: "xmark")
						} else {
							ProgressView()
								.controlSize(.mini)
								.accessibilityLabel("Loading page")
						}
					} else {
						Image(systemName: "arrow.clockwise")
					}
				}
				.labelStyle(.iconOnly)
				.frame(width: topBarItemWidth, height: topBarItemHeight)
			} primaryAction: {
				if controller?.isLoading == true {
					controller?.stopLoading()
				} else {
					controller?.reload()
				}
			}
			.clipShape(.rect(cornerRadius: 8))
			.accessibilityLabel(controller?.isLoading == true ? "Stop Loading" : "Reload")
			.accessibilityIdentifier("browser-reload")
		}
		.controlSize(.regular)
		.buttonSizing(.fitted)
		.buttonStyle(.bordered)
		.menuIndicator(.hidden)
	}
}
