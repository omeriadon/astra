import Defaults
import SwiftUI

let addressDisplayStyleSpacing = 8

struct BrowserGeneralSettingsView: View {
	@Default(.tabSwitchingOrder) private var tabSwitchingOrder
	@Default(.addressDisplayStyle) private var addressDisplayStyle
	@Default(.peekLevel) private var peekLevel
	@Default(.zoomOutInPeeks) private var zoomOutInPeeks
	@Default(.renameDownloadsWithAppleIntelligence) private var renameDownloadsWithAppleIntelligence

	var body: some View {
		List {
			Section("Tab Switching") {
				Picker("Control-Tab order", selection: $tabSwitchingOrder) {
					ForEach(TabSwitchingOrder.allCases) { order in
						Text(order.title)
							.tag(order)
					}
				}
				.accessibilityIdentifier("tab-switching-order-picker")
			}

			Section("Address Bar") {
				HStack(spacing: addressDisplayStyleSpacing) {
					ForEach(AddressDisplayStyle.allCases) { style in
						VStack {
							Spacer()

							Text(style.title)
						}
						.frame(height: 130)
						.background {
							Color.primary.opacity(addressDisplayStyle == style ? 0.3 : 0.1)
								.clipShape(RoundedRectangle(cornerRadius: 15))
						}
						.strokeBorder(.white.opacity(addressDisplayStyle == style ? 0.6 : 0.3), lineWidth: 1)
						.animation(.smooth, value: addressDisplayStyle == style)
						.onTapGesture {
							addressDisplayStyle = style
						}
						.containerRelativeFrame(
							.horizontal,
							count: 3,
							span: 1,
							spacing: addressDisplayStyleSpacing
						)
					}
				}
				.background {
					Color.primary.opacity(0.1)
						.clipShape(RoundedRectangle(cornerRadius: 15))
				}
				.accessibilityIdentifier("address-display-style-picker")
			}

			Section("Peek") {
				Picker("Levels", selection: $peekLevel) {
					ForEach(PeekLevel.allCases) { level in
						Text(level.title)
							.tag(level)
					}
				}
				.accessibilityIdentifier("peek-level-picker")

				if peekLevel != .none {
					Toggle("Zoom out in Peeks", isOn: $zoomOutInPeeks)
						.accessibilityIdentifier("zoom-out-in-peeks-toggle")
				}
			}

			Section("Website Data") {
				Button(role: .destructive, action: FaviconStore.shared.clear) {
					Label("Clear All Favicons", systemImage: "trash")
				}
				.disabled(FaviconStore.shared.isEmpty)
				.accessibilityIdentifier("clear-all-favicons")
			}

			Section("Downloads") {
				Toggle("Rename downloads with Apple Intelligence", isOn: $renameDownloadsWithAppleIntelligence)
					.accessibilityLabel("Rename downloads with Apple Intelligence")
					.accessibilityIdentifier("rename-downloads-with-apple-intelligence")
			}
		}
		.scrollContentBackground(.hidden)
		.listStyle(.sidebar)
	}
}
