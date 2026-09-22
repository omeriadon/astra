import CoreGraphics
import Foundation

struct PeekRequest: Identifiable, Equatable {
	let id = UUID()
	let url: URL
	let point: CGPoint
	let depth: Int

	static func == (lhs: PeekRequest, rhs: PeekRequest) -> Bool {
		lhs.id == rhs.id
	}
}
