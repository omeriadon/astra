import Foundation

@main
struct HistoryPolicyCheck {
	static func main() {
		let now = Date(timeIntervalSince1970: 1_800_000_000)
		let earlier = now.addingTimeInterval(-60)
		let firstURL = URL(string: "https://user:secret@example.com/path")!
		let normalized = BrowserVisit.normalizedURL(firstURL)!
		assert(normalized.user == nil && normalized.password == nil)
		assert(BrowserVisit.normalizedURL(URL(string: "astra://settings")!) == nil)
		let legacyData = Data(#"{"url":"https://user:secret@example.com/path","title":"Old","visitedAt":100}"#.utf8)
		let legacyVisit = try! JSONDecoder().decode(BrowserVisit.self, from: legacyData)
		let repeatedLegacyVisit = try! JSONDecoder().decode(BrowserVisit.self, from: legacyData)
		assert(legacyVisit.id == repeatedLegacyVisit.id)
		assert(legacyVisit.url.user == nil && legacyVisit.url.password == nil)
		assert(legacyVisit.modifiedAt == .distantPast)

        let older = BrowserVisit(
	id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
	url: normalized,
	title: "Old title",
	visitedAt: earlier,
	modifiedAt: earlier
)
        let newer = BrowserVisit(
	id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
	url: normalized,
	title: "Current title",
	visitedAt: now,
	modifiedAt: now
)
        let other = BrowserVisit(
	url: URL(string: "https://other.example/")!,
	title: "Other",
	visitedAt: now,
	modifiedAt: now
)

        assert(BrowserVisit.matching([older, newer, other], query: "current").map(\.id) == [newer.id])
        assert(BrowserVisit.inRange([older, newer, other], from: earlier, until: now).map(\.id) == [older.id])
		let summary = BrowserVisit.summaries([older, newer, other]).first { $0.url == normalized }
        assert(summary?.visitCount == 2)
        assert(summary?.title == "Current title")
		assert(summary?.lastVisitedAt == now)
		assert(BrowserVisit.retained([older, newer], days: 1, now: now) == [older, newer])
		assert(BrowserVisit.retained([older, newer], days: 0, now: now) == [older, newer])

        var updated = older
        updated.updateTitle("Old title", at: now)
        assert(updated.modifiedAt == earlier)
		updated.updateTitle("Renamed", at: now)
		assert(updated.modifiedAt == now)

		var restoredPolicy = BrowserVisitPolicy(suppressInitialVisit: true)
		assert(!restoredPolicy.didCommit(normalized, navigationID: 1))
		assert(!restoredPolicy.didChangeSameDocument(to: normalized, navigationID: 1))
		assert(restoredPolicy.didChangeSameDocument(to: URL(string: "https://example.com/next")!, navigationID: 1))
		assert(restoredPolicy.didCommit(normalized, navigationID: 2))
		assert(!restoredPolicy.didChangeSameDocument(to: normalized, navigationID: 2))
		var failedRestorePolicy = BrowserVisitPolicy(suppressInitialVisit: true)
		assert(!failedRestorePolicy.didCommit(URL(string: "file:///tmp/page.html")!, navigationID: 1))
		assert(failedRestorePolicy.didCommit(normalized, navigationID: 2))
		var userReplacedFailedRestorePolicy = BrowserVisitPolicy(suppressInitialVisit: true)
		userReplacedFailedRestorePolicy.userInitiatedNavigation()
		assert(userReplacedFailedRestorePolicy.didCommit(normalized, navigationID: 1))

        print("09 history policy checks passed")
	}
}
