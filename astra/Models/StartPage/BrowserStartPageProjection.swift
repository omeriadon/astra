import Foundation

nonisolated enum BrowserStartPageProjection {
	static func recent(_ visits: [BrowserVisit], isPrivate: Bool, limit: Int = 8) -> [BrowserVisit] {
		guard !isPrivate, limit > 0 else { return [] }
		return visits.sorted {
			$0.visitedAt == $1.visitedAt
				? $0.id.uuidString < $1.id.uuidString
				: $0.visitedAt > $1.visitedAt
		}.prefix(limit).map(\.self)
	}

	static func frequent(_ visits: [BrowserVisit], isPrivate: Bool, limit: Int = 8) -> [BrowserVisitSummary] {
		guard !isPrivate, limit > 0 else { return [] }
		return BrowserVisit.summaries(visits).sorted {
			if $0.visitCount != $1.visitCount {
				return $0.visitCount > $1.visitCount
			}
			if $0.lastVisitedAt != $1.lastVisitedAt {
				return $0.lastVisitedAt > $1.lastVisitedAt
			}
			return $0.url.absoluteString < $1.url.absoluteString
		}.prefix(limit).map(\.self)
	}
}
