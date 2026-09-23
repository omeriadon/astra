import Foundation

struct BrowserScrollPosition: Codable, Equatable, Sendable {
	var x: Double
	var y: Double

	nonisolated static let zero = Self(x: 0, y: 0)
}
