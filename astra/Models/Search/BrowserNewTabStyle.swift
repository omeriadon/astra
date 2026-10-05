import Foundation

enum BrowserNewTabStyle: String, CaseIterable, Identifiable {
	case page
	case overlay

	var id: String {
		rawValue
	}

	var title: String {
		switch self {
			case .page: "Sidebar Tab"
			case .overlay: "Spotlight Overlay"
		}
	}

	var symbol: String {
		switch self {
			case .page: "sidebar.left"
			case .overlay: "magnifyingglass"
		}
	}

	var description: String {
		switch self {
			case .page: "Create a sidebar item with its own New Tab page."
			case .overlay: "Search over the current page. Open a new tab when you choose a website."
		}
	}
}
