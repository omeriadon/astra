import Foundation

// Run: swiftc browser/Models/BrowserHistory.swift browser/Models/BrowserScrollPosition.swift browser/Models/OpenTab.swift browser/Models/OpenPeek.swift Checks/BrowserHistoryCheck.swift -o /tmp/browser-history-check && /tmp/browser-history-check
@main
struct BrowserHistoryCheck {
	static func main() throws {
		let home = URL(string: "https://monkeytype.com/")!
		let leaderboard = URL(string: "https://monkeytype.com/leaderboards")!
		let canonical = URL(string: "https://monkeytype.com/leaderboards?type=allTime&mode=time&mode2=15&language=english&page=1")!
		let other = URL(string: "https://example.com/")!
		var tab = BrowserHistory(initialURL: home)
		tab.beginVisit()
		tab.record(leaderboard)
		tab.record(canonical)
		assert(tab.entries == [home, canonical])
		assert(tab.canGoBack && !tab.canGoForward)

		var menu = tab
		assert(tab.select(tab.index - 1) == menu.select(0))
		tab.record(home)
		assert(!tab.canGoBack && tab.canGoForward)
		assert(tab.select(tab.index + 1) == canonical)
		tab.record(canonical)
		assert(tab.entries == [home, canonical])

		// A rewrite after selecting an older entry must preserve forward history.
		tab.beginVisit()
		tab.record(other)
		assert(tab.select(1) == canonical)
		tab.record(leaderboard)
		tab.record(canonical)
		assert(tab.entries == [home, canonical, other])
		assert(tab.index == 1 && tab.canGoForward)

		// Persist two tabs together with different current positions.
		let second = BrowserHistory(initialURL: other)
		let snapshots = [
			OpenTab(
				url: tab.currentURL,
				history: tab.entries,
				historyIndex: tab.index,
				scrollPosition: BrowserScrollPosition(x: 0, y: 420),
				isHibernated: true
			),
			OpenTab(url: second.currentURL, history: second.entries, historyIndex: second.index),
		]
		let restored = try JSONDecoder().decode([OpenTab].self, from: JSONEncoder().encode(snapshots))
		assert(restored == snapshots)
		assert(restored[0].scrollPosition.y == 420 && restored[0].isHibernated)
		var firstRestored = BrowserHistory(entries: restored[0].history, index: restored[0].historyIndex)
		let secondRestored = BrowserHistory(entries: restored[1].history, index: restored[1].historyIndex)
		assert(firstRestored.currentURL == canonical && firstRestored.canGoForward)
		assert(firstRestored.select(0) == home)
		firstRestored.beginVisit()
		firstRestored.record(leaderboard)
		assert(firstRestored.entries == [home, leaderboard])
		assert(secondRestored.entries == [other] && secondRestored.index == 0)
		assert(tab.entries == [home, canonical, other])
		assert(firstRestored.select(-1) == nil)
		assert(firstRestored.select(99) == nil)
		assert(!BrowserHistory().canGoBack && !BrowserHistory().canGoForward)
		print("PASS: selection, redirects, branching, tab isolation, and per-tab persistence")
	}
}
