import Foundation

nonisolated enum BrowserStartPageProjection {
	static func recent(_ visits: [BrowserVisit], isPrivate: Bool, limit: Int = 8) -> [BrowserVisit] {
		guard !isPrivate, limit > 0 else { return [] }
		// Only a handful of recent visits appear on the start page. Keep
		// the best 'limit' entries instead of sorting/copying the entire
		// browsing history on each navigation.
		if limit >= 64 {
			return Array(visits.sorted {
				$0.visitedAt == $1.visitedAt
					? $0.id.uuidString < $1.id.uuidString
					: $0.visitedAt > $1.visitedAt
			}.prefix(limit))
		}
		var recent: [BrowserVisit] = []
		recent.reserveCapacity(min(limit, visits.count))
		for visit in visits {
			let insertion = recent.firstIndex {
				visit.visitedAt > $0.visitedAt
					|| (visit.visitedAt == $0.visitedAt && visit.id.uuidString < $0.id.uuidString)
			}
			if let insertion {
				recent.insert(visit, at: insertion)
				if recent.count > limit { recent.removeLast() }
			} else if recent.count < limit {
				recent.append(visit)
			}
		}
		return recent
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
