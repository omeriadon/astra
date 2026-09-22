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
			} primaryAction: {
				controller?.goBack()
			}
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
			.accessibilityIdentifier("browser-forward")

			Menu {
				Button("Force Reload", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
					controller?.reloadFromOrigin()
				}
			} label: {
				Label {
					Text("Reload")
				} icon: {
					Image(systemName: "arrow.clockwise")
						.symbolEffect(.pulse, options: .repeating, isActive: isReloadAnimating)
						.symbolEffect(.breathe, options: .repeating, isActive: isReloadAnimating)
						.symbolEffect(.rotate, options: .repeating, isActive: isReloadAnimating)
				}
				.labelStyle(.iconOnly)
				.frame(width: topBarItemWidth, height: topBarItemHeight)
			} primaryAction: {
				controller?.reload()
			}
			.accessibilityIdentifier("browser-reload")
		}
		.controlSize(.regular)
		.buttonSizing(.fitted)
		.buttonStyle(.bordered)
		.menuIndicator(.hidden)
		.clipShape(.rect(cornerRadius: 8))
	}

	private var isReloadAnimating: Bool {
		controller?.isLoading == true && !reduceMotion
	}
}
