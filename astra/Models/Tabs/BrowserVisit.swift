import Foundation

nonisolated struct BrowserVisit: Codable, Identifiable, Equatable, Sendable {
	var id: UUID = .init()
	var url: URL
	var title: String
	var visitedAt: Date = .now

	static func retained(_ visits: [Self], days: Int, now: Date = .now) -> [Self] {
		guard days > 0 else { return visits }
		let cutoff = now.addingTimeInterval(-Double(days) * 86400)
		return visits.filter { $0.visitedAt >= cutoff }
	}
}
