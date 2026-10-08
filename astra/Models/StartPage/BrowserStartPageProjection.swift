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
		let summaries = BrowserVisit.summaries(visits, sortByRecency: false)
		let outranks: (BrowserVisitSummary, BrowserVisitSummary) -> Bool = { lhs, rhs in
			if lhs.visitCount != rhs.visitCount { return lhs.visitCount > rhs.visitCount }
			if lhs.lastVisitedAt != rhs.lastVisitedAt { return lhs.lastVisitedAt > rhs.lastVisitedAt }
			return lhs.url.absoluteString < rhs.url.absoluteString
		}
		if limit >= 64 {
			return Array(summaries.sorted(by: outranks).prefix(limit))
		}
		// Start page normally shows eight sites: maintain a bounded top-K
		// list instead of sorting every unique history URL twice.
		var frequent: [BrowserVisitSummary] = []
		frequent.reserveCapacity(min(limit, summaries.count))
		for summary in summaries {
			if let index = frequent.firstIndex(where: { outranks(summary, $0) }) {
				frequent.insert(summary, at: index)
				if frequent.count > limit { frequent.removeLast() }
			} else if frequent.count < limit {
				frequent.append(summary)
			}
		}
		return frequent
	}
}
