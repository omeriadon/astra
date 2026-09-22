import SwiftUI

struct BrowserSettingsView: View {
	@AppStorage("tabSwitchingOrder") private var tabSwitchingOrder = TabSwitchingOrder.visibleTabList.rawValue
	@AppStorage("addressDisplayStyle") private var addressDisplayStyle = AddressDisplayStyle.simple.rawValue
	@AppStorage("topBarBackgroundStyle") private var topBarBackgroundStyle = TopBarBackgroundStyle.blur.rawValue

	var body: some View {
		List {
			Section("Tab Switching") {
				Picker("Control-Tab order", selection: $tabSwitchingOrder) {
					ForEach(TabSwitchingOrder.allCases) { order in
						Text(order.title)
							.tag(order.rawValue)
					}
				}
				.accessibilityIdentifier("tab-switching-order-picker")
			}

			Section("Address Bar") {
				Picker("Display", selection: $addressDisplayStyle) {
					ForEach(AddressDisplayStyle.allCases) { style in
						Text(style.title)
							.tag(style.rawValue)
					}
				}
				.accessibilityIdentifier("address-display-style-picker")
			}

			Section("Top Bar") {
				Picker("Background", selection: $topBarBackgroundStyle) {
					ForEach(TopBarBackgroundStyle.allCases) { style in
						Text(style.title)
							.tag(style.rawValue)
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
