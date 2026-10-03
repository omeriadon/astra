import Foundation

enum PeekLevel: String, CaseIterable, Identifiable {
	case none
	case one
	case two

	var id: String {
		rawValue
	}

	var title: String {
		switch self {
			case .none: "No Peek"
			case .one: "1 level"
			case .two: "2 levels"
		}
	}

	var maximumDepth: Int {
		switch self {
			case .none: 0
			case .one: 1
			case .two: 2
		}
	}
}
