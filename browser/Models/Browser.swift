import Foundation
import Observation

@Observable
final class Browser {
	private(set) var tabs: [BrowserTab]
	private(set) var selectedTabID: UUID

	var selectedTab: BrowserTab? {
		tabs.first { $0.id == selectedTabID }
	}

	init() {
		let tab = BrowserTab()
		tabs = [tab]
		selectedTabID = tab.id
	}

	@discardableResult
	func addTab() -> BrowserTab {
		let tab = BrowserTab()
		tabs.append(tab)
		selectedTabID = tab.id
		return tab
	}

	func selectTab(_ id: UUID) {
		guard tabs.contains(where: { $0.id == id }) else { return }
		selectedTabID = id
	}

	func closeTab(_ id: UUID) {
		guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
		let wasSelected = selectedTabID == id
		tabs.remove(at: index)

		if tabs.isEmpty {
			addTab()
		} else if wasSelected {
			selectedTabID = tabs[min(index, tabs.count - 1)].id
		}
	}
}
