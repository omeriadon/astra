import Foundation

enum TopBarBackgroundStyle: String, CaseIterable, Identifiable {
	case glass
	case blur

	var id: String {
		rawValue
	}

	var title: String {
		switch self {
			case .glass: "Glass"
			case .blur: "Blur"
		}
	}
}
