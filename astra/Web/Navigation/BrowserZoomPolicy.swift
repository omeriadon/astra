import Foundation

enum BrowserZoomPolicy {
	static let defaultZoom = 1.0
	static let range = 0.25 ... 5.0

	static func clamp(_ zoom: Double) -> Double {
		guard zoom.isFinite else { return defaultZoom }
		return min(max(zoom, range.lowerBound), range.upperBound)
	}

}

struct BrowserFindGeneration {
	private(set) var value = 0

	@discardableResult
	mutating func advance() -> Int {
		value += 1
		return value
	}

	func accepts(_ generation: Int) -> Bool {
		generation == value
	}
}
