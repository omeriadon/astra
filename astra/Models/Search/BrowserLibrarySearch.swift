import Foundation
import Observation

nonisolated struct BrowserLibrarySearchEntry: Sendable {
	let id: UUID
	let url: URL
	let title: String
	let isTab: Bool
	let bonus: Double
}
nonisolated struct BrowserLibrarySearchMatch: Sendable {
	let entry: BrowserLibrarySearchEntry
	let score: Double
}

actor BrowserLibrarySearchWorker {
	private var request: BrowserLibrarySearchModel.Request?
	private var prepared: [(BrowserLibrarySearchEntry, BrowserSearchMatching.PreparedText, BrowserSearchMatching.PreparedText)] = []

	func search(_ entries: [BrowserLibrarySearchEntry], request: BrowserLibrarySearchModel.Request) throws -> [BrowserLibrarySearchMatch] {
		let locale = Locale(identifier: request.localeID)
		if self.request?.revision != request.revision || self.request?.tabRevision != request.tabRevision || self.request?.localeID != request.localeID {
			var next: [(BrowserLibrarySearchEntry, BrowserSearchMatching.PreparedText, BrowserSearchMatching.PreparedText)] = []
			for (index, entry) in entries.enumerated() {
				if index.isMultiple(of: 64) { try Task.checkCancellation() }
				next.append((entry, .init(entry.title, locale: locale), .init(entry.url.absoluteString, locale: locale)))
			}
			prepared = next
			self.request = request
		}
		let query = BrowserSearchMatching.PreparedQuery(request.query, locale: locale)
		var matches: [BrowserLibrarySearchMatch] = []
		for (index, item) in prepared.enumerated() {
			if index.isMultiple(of: 64) { try Task.checkCancellation() }
			let score = max(BrowserSearchMatching.score(query, in: item.1), BrowserSearchMatching.score(query, in: item.2))
			if score > 0 { matches.append(.init(entry: item.0, score: score + item.0.bonus)) }
		}
		matches.sort { $0.score == $1.score ? $0.entry.id.uuidString < $1.entry.id.uuidString : $0.score > $1.score }
		var tabURLs: Set<URL> = [], bookmarkURLs: Set<URL> = []
		return matches.filter {
			if $0.entry.isTab { return tabURLs.count < 4 && tabURLs.insert($0.entry.url).inserted }
			return bookmarkURLs.count < 4 && bookmarkURLs.insert($0.entry.url).inserted
		}
	}
}

@MainActor @Observable final class BrowserLibrarySearchModel {
	nonisolated struct Request: Hashable, Sendable {
		let query: String
		let revision: Int
		let tabRevision: Int
		var localeID = Locale.current.identifier
	}
	private struct Output { let request: Request; let matches: [BrowserLibrarySearchMatch] }
	private var outputs: [BrowserHistorySearchModel.Scope: Output] = [:]
	@ObservationIgnored private var tokens: [BrowserHistorySearchModel.Scope: UUID] = [:]
	@ObservationIgnored private var snapshot: (Int, Int, [BrowserLibrarySearchEntry])?
	@ObservationIgnored private let worker = BrowserLibrarySearchWorker()

	func matches(for request: Request, scope: BrowserHistorySearchModel.Scope) -> [BrowserLibrarySearchMatch] {
		outputs[scope].flatMap { $0.request == request ? $0.matches : nil } ?? []
	}
	func update(_ request: Request, scope: BrowserHistorySearchModel.Scope, entries: () -> [BrowserLibrarySearchEntry]) async {
		guard !Task.isCancelled else { return }
		let token = UUID()
		tokens[scope] = token
		guard !request.query.isEmpty else { outputs[scope] = nil; return }
		do {
			try await Task.sleep(for: .milliseconds(40))
			if snapshot?.0 != request.revision || snapshot?.1 != request.tabRevision {
				snapshot = (request.revision, request.tabRevision, entries())
			}
			let matches = try await worker.search(snapshot!.2, request: request)
			guard !Task.isCancelled, tokens[scope] == token else { return }
			outputs[scope] = Output(request: request, matches: matches)
		} catch { /* Superseded queries never publish. */ }
	}
}
