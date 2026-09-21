import SwiftUI

struct BrowserSettingsView: View {
	@AppStorage("tabSwitchingOrder") private var tabSwitchingOrder = TabSwitchingOrder.visibleTabList.rawValue
	@AppStorage("addressDisplayStyle") private var addressDisplayStyle = AddressDisplayStyle.simple.rawValue

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
		}
		.navigationTitle("Settings")
		.frame(minWidth: 360, minHeight: 180)
	}
}
