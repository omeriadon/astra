import Defaults
import SwiftUI

struct BrowserSettingsView: View {
	@Default(.tabSwitchingOrder) private var tabSwitchingOrder
	@Default(.addressDisplayStyle) private var addressDisplayStyle
	@Default(.topBarBackgroundStyle) private var topBarBackgroundStyle

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

			Section("Top Bar") {
				Picker("Background", selection: $topBarBackgroundStyle) {
					ForEach(TopBarBackgroundStyle.allCases) { style in
						Text(style.title)
							.tag(style)
					}
				}
				.accessibilityIdentifier("top-bar-background-style-picker")
			}

			Section("Website Data") {
				Button(role: .destructive, action: FaviconStore.shared.clear) {
					Label("Clear All Favicons", systemImage: "trash")
				}
				.disabled(FaviconStore.shared.isEmpty)
				.accessibilityIdentifier("clear-all-favicons")
			}
		}
		.navigationTitle("Settings")
		.frame(minWidth: 360, minHeight: 180)
	}
}
