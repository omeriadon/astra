import Foundation

@main
struct PreparedHistorySearchCheck {
	@MainActor static func main() async throws {
		let locale = Locale(identifier: "en_US")
		let now = Date(timeIntervalSince1970: 1_800_000_000)
		var visits = (0..<10000).map { index in
			BrowserVisit(url: URL(string: "https://example.com/\(index)")!,
				title: index.isMultiple(of: 3) ? "Café Alpha \(index)" : "Beta \(index)",
				visitedAt: now.addingTimeInterval(-Double(index) * 120))
		}
		visits.append(BrowserVisit(url: visits[3].url, title: "Renamed Alpha", visitedAt: now))
		let worker = BrowserHistorySearchWorker()
		for query in ["Alpha", "cafe", "alhpa", "example.com", "Beta 47", "no-match-here"] {
			let actual = try await worker.search(visits, revision: 1, query: query, locale: locale)
			precondition(actual == reference(visits, query: query), "Prepared ranking changed: \(query)")
		}
		let changed = [BrowserVisit(url: URL(string: "https://new.example/")!, title: "New Alpha", visitedAt: now)]
		let changedResult = try await worker.search(changed, revision: 2, query: "Alpha", locale: locale)
		precondition(changedResult.map(\.title) == ["New Alpha"], "History revision must invalidate prepared data")
		let cancelled = Task {
			withUnsafeCurrentTask { $0?.cancel() }
			return try await worker.search(visits, revision: 3, query: "Alpha", locale: locale)
		}
		do { _ = try await cancelled.value; preconditionFailure("Cancelled ranking must throw") }
		catch is CancellationError { }

		let model = BrowserHistorySearchModel()
		let first = BrowserHistorySearchModel.Request(query: "Alpha", revision: 1)
		let second = BrowserHistorySearchModel.Request(query: "Beta", revision: 1)
		let old = Task { await model.update(first, scope: .newTab, visits: visits) }
		await Task.yield()
		old.cancel()
		await model.update(second, scope: .newTab, visits: visits)
		await old.value
		precondition(model.matches(for: first, scope: .newTab).isEmpty, "Never expose results for another query")
		precondition(!model.matches(for: second, scope: .newTab).isEmpty)
		await model.update(first, scope: .address, visits: visits)
		precondition(!model.matches(for: first, scope: .address).isEmpty)
		precondition(!model.matches(for: second, scope: .newTab).isEmpty, "Address and new-tab queries must be independent")
		model.invalidate(before: 2)
		precondition(model.matches(for: second, scope: .newTab).isEmpty, "Deletion must hide old results immediately")
		print("Prepared history ranking, revisions, cancellation and independent surfaces passed")
	}

	// The previous synchronous aggregation/ranking, retained as a behavioral oracle.
	static func reference(_ visits: [BrowserVisit], query: String) -> [BrowserHistorySearchMatch] {
		var summaries: [URL: (BrowserVisit, Int)] = [:]
		let newest = visits.map(\.visitedAt).max() ?? .distantPast
		for visit in visits {
			if let old = summaries[visit.url] {
				let latest = visit.visitedAt > old.0.visitedAt ||
					(visit.visitedAt == old.0.visitedAt && visit.id.uuidString < old.0.id.uuidString) ? visit : old.0
				summaries[visit.url] = (latest, old.1 + 1)
			} else { summaries[visit.url] = (visit, 1) }
		}
		let query = BrowserSearchMatching.normalized(query)
		return Array(summaries.values.compactMap { visit, count -> BrowserHistorySearchMatch? in
			let score = max(BrowserSearchMatching.score(normalizedQuery: query, in: visit.title),
				BrowserSearchMatching.score(normalizedQuery: query, in: visit.url.host ?? ""),
				BrowserSearchMatching.score(normalizedQuery: query, in: visit.url.absoluteString))
			guard score > 0 else { return nil }
			let age = max(0, newest.timeIntervalSince(visit.visitedAt) / 86400)
			return .init(id: visit.id, url: visit.url, title: visit.title,
				score: score + min(Double(count), 20) * 0.002 + (1 / (1 + age / 365)) * 0.02)
		}.sorted {
			$0.score == $1.score ? $0.id.uuidString < $1.id.uuidString : $0.score > $1.score
		}.prefix(4))
	}
}
