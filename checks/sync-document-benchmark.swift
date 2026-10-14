import Foundation

@main
struct SyncDocumentBenchmark {
	static func main() throws {
		let now = Date(timeIntervalSince1970: 1_790_000_000)
		let urls = (0 ..< 15000).map { URL(string: "https://international-publication.example/articles/\($0)")! }
		let tabs = (0 ..< 400).map { OpenTab(url: urls[$0], modifiedAt: now) }
		let bookmarks = (0 ..< 1800).map { Bookmark(name: "Bookmark \($0)", url: urls[$0], modifiedAt: now) }
		let visits = urls.enumerated().map { BrowserVisit(url: $0.element, title: "Visit \($0.offset)", visitedAt: now, modifiedAt: now) }
		let workspace = BrowserWorkspace.migrated(tabs: tabs, selectedTabID: tabs[0].id, theme: BrowserTheme())
		let document = BrowserSyncDocument(tabs: tabs, workspace: workspace, bookmarks: bookmarks, history: visits, browser: BrowserSnapshot(selectedTabID: tabs[0].id), settings: [:])
		func measure<T>(_ stage: String, _ operation: () throws -> T) rethrows -> T {
			let start = ProcessInfo.processInfo.systemUptime
			let result = try operation()
			print("stage=\(stage) elapsed_ms=\((ProcessInfo.processInfo.systemUptime - start) * 1000)")
			return result
		}
		let projected = measure("projection") { document.portableProjection() }
		let valid = measure("validation") { projected.hasValidStructure }
		precondition(valid)
		let encoded = try measure("encoding") { try JSONEncoder().encode(projected) }
		let decoded = try measure("decoding") { try JSONDecoder().decode(BrowserSyncDocument.self, from: encoded) }
		precondition(decoded == projected)
		let unchanged = measure("unchanged_projection") { projected.portableProjection() }
		precondition(unchanged == projected)
		print("tabs=\(tabs.count) bookmarks=\(bookmarks.count) visits=\(visits.count) bytes=\(encoded.count)")
	}
}
