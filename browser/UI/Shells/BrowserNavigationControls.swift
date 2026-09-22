import SwiftUI
import WebKit

struct BrowserNavigationControls: View {
	let controller: BrowserController?

	private var backItems: [WKBackForwardListItem] {
		controller?.backHistoryItems ?? []
	}

	private var forwardItems: [WKBackForwardListItem] {
		controller?.forwardHistoryItems ?? []
	}

	private func navigationLabel(
		_ title: String,
		systemImage: String,
		foregroundStyle: HierarchicalShapeStyle = .primary
	) -> some View {
		Label(title, systemImage: systemImage)
			.labelStyle(.iconOnly)
			.foregroundStyle(foregroundStyle)
			.frame(width: topBarItemWidth, height: topBarItemHeight)
	}

	var body: some View {
		HStack(spacing: 6) {
			Menu {
				if backItems.isEmpty {
					Button("No Back History", systemImage: "minus.circle") {}
						.disabled(true)
				} else {
					ForEach(backItems.enumerated(), id: \.offset) { _, item in
						Button(
							item.title ?? item.url.absoluteString,
							systemImage: "clock.arrow.circlepath"
						) {
							controller?.go(to: item)
						}
					}
				}
			} label: {
				navigationLabel(
					"Back",
					systemImage: "chevron.backward",
					foregroundStyle:
					controller?.canGoBack == true
						? .primary
						: .tertiary
				)
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
						Button(
							item.title ?? item.url.absoluteString,
							systemImage: "clock.arrow.circlepath"
						) {
							controller?.go(to: item)
						}
					}
				}
			} label: {
				navigationLabel(
					"Forward",
					systemImage: "chevron.forward",
					foregroundStyle:
					controller?.canGoForward == true
						? .primary
						: .tertiary
				)
			} primaryAction: {
				controller?.goForward()
			}
			.clipShape(.rect(cornerRadius: 8))
			.accessibilityIdentifier("browser-forward")

			Menu {
				Button(
					"Force Reload",
					systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
				) {
					controller?.reloadFromOrigin()
				}
			} label: {
				Label("Reload", systemImage: "arrow.clockwise")
					.hidden()
					.labelStyle(.iconOnly)
					.frame(
						width: topBarItemWidth,
						height: topBarItemHeight
					)
			} primaryAction: {
				if controller?.isLoading == true {
					controller?.stopLoading()
				} else {
					controller?.reload()
				}
			}
			.overlay {
				ZStack {
					if controller?.isLoading == true {
						Image(systemName: "xmark")
							.transition(.blurReplace)
					} else {
						Image(systemName: "arrow.clockwise")
							.transition(.blurReplace)
					}
				}
				.animation(
					.bouncy(duration: 0.3),
					value: controller?.isLoading
				)
				.allowsHitTesting(false)
			}
			.clipShape(.rect(cornerRadius: 8))
			.accessibilityLabel(
				controller?.isLoading == true
					? "Stop Loading"
					: "Reload"
			)
			.accessibilityIdentifier("browser-reload")
		}
		.controlSize(.regular)
		.buttonSizing(.fitted)
		.buttonStyle(.bordered)
		.menuIndicator(.hidden)
		.menuStyle(.borderedButton)
	}
}
