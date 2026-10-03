import Foundation

enum AddressDisplayStyle: String, CaseIterable, Identifiable {
	case full
	case simple
	case dimmed

	var id: String {
		rawValue
	}

	var title: String {
		switch self {
			case .full: "Full"
			case .simple: "Simple"
			case .dimmed: "Dimmed"
		}
	}
}
