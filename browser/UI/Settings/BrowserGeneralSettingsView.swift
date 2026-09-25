import Defaults
import SwiftUI

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
				Picker("Display", selection: $addressDisplayStyle) {
					ForEach(AddressDisplayStyle.allCases) { style in
						Text(style.title)
							.tag(style)
					}
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
	}
}
