import Foundation

enum TabSwitchingOrder: String, CaseIterable, Identifiable {
	case visibleTabList
	case mostRecentlyUsed

	var id: String {
		rawValue
	}

	var title: String {
		switch self {
			case .visibleTabList: "Visible tab list"
			case .mostRecentlyUsed: "Most recently used"
		}
	}
}
