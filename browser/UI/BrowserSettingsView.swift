import SwiftUI

struct BrowserSettingsView: View {
	@AppStorage("tabSwitchingOrder") private var tabSwitchingOrder = TabSwitchingOrder.visibleTabList.rawValue

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
		}
		.navigationTitle("Settings")
		.frame(minWidth: 360, minHeight: 180)
	}
}
