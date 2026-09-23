import Foundation

struct BrowserScrollPosition: Codable, Equatable {
	var x: Double
	var y: Double

	static let zero = Self(x: 0, y: 0)
}
