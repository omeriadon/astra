import Foundation
import Observation

/// Value-only history records cross the actor boundary; Browser/UI closures never do.
nonisolated struct BrowserHistorySearchMatch: Equatable, Sendable {
	let id: UUID
	let url: URL
	let title: String
	let score: Double
}

actor BrowserHistorySearchWorker {
	private nonisolated struct Entry: Sendable {
		let visit: BrowserVisit
		let count: Int
		let title: BrowserSearchMatching.PreparedText
		let host: BrowserSearchMatching.PreparedText
		let address: BrowserSearchMatching.PreparedText
	}

	private var revision: Int?
	private var minimumRevision = 0
	private var localeID: String?
	private var entries: [Entry] = []
	private var newestVisit = Date.distantPast

	func invalidate(before revision: Int) {
		minimumRevision = max(minimumRevision, revision)
		guard let previous = self.revision, previous < revision else { return }
		entries.removeAll()
		self.revision = nil
	}

	func search(_ visits: [BrowserVisit], revision: Int, query: String, locale: Locale) throws -> [BrowserHistorySearchMatch] {
		try Task.checkCancellation()
		guard revision >= minimumRevision else { throw CancellationError() }
		if self.revision != revision || localeID != locale.identifier {
			var summaries: [URL: (visit: BrowserVisit, count: Int)] = [:]
			var newest = Date.distantPast
			for (offset, visit) in visits.enumerated() {
				if offset.isMultiple(of: 64) {
					try Task.checkCancellation()
				}
				newest = max(newest, visit.visitedAt)
				if var existing = summaries[visit.url] {
					existing.count += 1
					if visit.visitedAt > existing.visit.visitedAt ||
						(visit.visitedAt == existing.visit.visitedAt && visit.id.uuidString < existing.visit.id.uuidString)
					{
						existing.visit = visit
					}
					summaries[visit.url] = existing
				} else {
					summaries[visit.url] = (visit, 1)
				}
			}
			var prepared: [Entry] = []
			prepared.reserveCapacity(summaries.count)
			for (offset, value) in summaries.values.enumerated() {
				if offset.isMultiple(of: 64) {
					try Task.checkCancellation()
				}
				prepared.append(Entry(visit: value.visit, count: value.count,
				                      title: .init(value.visit.title, locale: locale),
				                      host: .init(value.visit.url.host ?? "", locale: locale),
				                      address: .init(value.visit.url.absoluteString, locale: locale)))
			}
			try Task.checkCancellation()
			entries = prepared
			newestVisit = newest
			self.revision = revision
			localeID = locale.identifier
		}
		let preparedQuery = BrowserSearchMatching.PreparedQuery(query, locale: locale)
		var matches: [BrowserHistorySearchMatch] = []
		for (offset, entry) in entries.enumerated() {
			if offset.isMultiple(of: 64) {
				try Task.checkCancellation()
			}
			let match = max(BrowserSearchMatching.score(preparedQuery, in: entry.title),
			                BrowserSearchMatching.score(preparedQuery, in: entry.host),
			                BrowserSearchMatching.score(preparedQuery, in: entry.address))
			guard match > 0 else { continue }
			let age = max(0, newestVisit.timeIntervalSince(entry.visit.visitedAt) / 86400)
			matches.append(.init(id: entry.visit.id, url: entry.visit.url, title: entry.visit.title,
			                     score: match + min(Double(entry.count), 20) * 0.002 + (1 / (1 + age / 365)) * 0.02))
		}
		try Task.checkCancellation()
		// Only four history rows can survive BrowserSearchResult.ranked. Keep its exact tie order.
		return Array(matches.sorted {
			$0.score == $1.score ? $0.id.uuidString < $1.id.uuidString : $0.score > $1.score
		}.prefix(4))
	}
}

@MainActor
@Observable
final class BrowserHistorySearchModel {
	nonisolated enum Scope: Hashable, Sendable { case newTab, address }
	nonisolated struct Request: Equatable, Hashable, Sendable {
		let query: String
		let revision: Int
		var localeID = Locale.current.identifier
	}

	private struct Output {
		let request: Request
		let matches: [BrowserHistorySearchMatch]
	}

	private var outputs: [Scope: Output] = [:]
	@ObservationIgnored private var requests: [Scope: UUID] = [:]
	@ObservationIgnored private let worker = BrowserHistorySearchWorker()

	func invalidate(before revision: Int) {
		requests.removeAll()
		outputs.removeAll()
		Task { await worker.invalidate(before: revision) }
	}

	func matches(for request: Request, scope: Scope) -> [BrowserHistorySearchMatch] {
		guard let output = outputs[scope], output.request == request else { return [] }
		return output.matches
	}

	/// Called by a view task, never during body evaluation. SwiftUI cancels it on query changes/disappearance.
	func update(_ request: Request, scope: Scope, visits: [BrowserVisit]) async {
		let token = UUID()
		requests[scope] = token
		guard !request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			outputs[scope] = nil
			return
		}
		do {
			let matches = try await worker.search(visits, revision: request.revision, query: request.query,
			                                      locale: Locale(identifier: request.localeID))
			guard !Task.isCancelled, requests[scope] == token else { return }
			outputs[scope] = Output(request: request, matches: matches)
		} catch is CancellationError {
			// A cancelled query must never publish, including after a history deletion.
		} catch {
			// Worker currently throws cancellation only; leave no stale rows for this request.
			if !Task.isCancelled, requests[scope] == token {
				outputs[scope] = nil
			}
		}
	}
}
