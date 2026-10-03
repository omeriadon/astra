import Foundation

@main
struct StartPagePreferencesCheck {
	static func main() {
		var preferences = BrowserStartPagePreferences.default
		preferences.hiddenModules = [.recent, .favourites]
		preferences.move(.recentlyClosed, by: -1)

		let decoded = BrowserStartPagePreferences.decode(preferences.encoded)
		assert(decoded == preferences)
		assert(decoded?.moduleOrder[2] == .recentlyClosed)
		assert(decoded?.isVisible(.frequent) == true)
		assert(decoded?.isVisible(.recent) == false)

		let reorderedHidden = BrowserStartPagePreferences(
			version: preferences.version,
			moduleOrder: preferences.moduleOrder,
			hiddenModules: [.favourites, .recent]
		)
		assert(preferences.encoded == reorderedHidden.encoded)
		assert(BrowserStartPagePreferences.decode("{\"version\":2}") == nil)
		assert(BrowserStartPagePreferences.decode("invalid") == nil)

		let older = BrowserVisit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, url: URL(string: "https://example.com/old")!, title: "Old", visitedAt: .now.addingTimeInterval(-100))
		let newer = BrowserVisit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, url: URL(string: "https://example.com/new")!, title: "New", visitedAt: .now)
		let visits = [older, newer, older]
		assert(BrowserStartPageProjection.recent(visits, isPrivate: false).first == newer)
		assert(BrowserStartPageProjection.frequent(visits, isPrivate: false).first?.url == older.url)
		assert(BrowserStartPageProjection.frequent(visits, isPrivate: false).first?.visitCount == 2)
		assert(BrowserStartPageProjection.recent(visits, isPrivate: true).isEmpty)
		assert(BrowserStartPageProjection.frequent(visits, isPrivate: true).isEmpty)
	}
}
