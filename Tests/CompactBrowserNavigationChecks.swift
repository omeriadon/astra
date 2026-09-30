// swiftc astra/UI/Shell/CompactBrowserNavigation.swift Tests/CompactBrowserNavigationChecks.swift -o /tmp/astra-navigation-checks && /tmp/astra-navigation-checks
import Foundation

@main
struct CompactBrowserNavigationChecks {
	static func main() {
		var navigation = CompactBrowserNavigation()
		let tabID = UUID().uuidString
		assert(!navigation.showsPage)

		// Opening the current tab must navigate even when selection did not change.
		for _ in 0 ..< 3 {
			navigation.open(from: tabID)
			assert(navigation.showsPage)
			assert(navigation.sourceID == tabID)
			navigation.showsPage = false
		}

		// Settings, history, and new tabs change the presented content without
		// popping navigation or replacing the original return-transition source.
		navigation.open(from: tabID)
		for source in ["sidebar", "toolbar-new-tab", UUID().uuidString] {
			navigation.open(from: source)
			assert(navigation.showsPage)
			assert(navigation.sourceID == tabID)
		}

		navigation.showsPage = false
		navigation.open(from: "sidebar")
		assert(navigation.showsPage)
		assert(navigation.sourceID == "sidebar")
		print("Compact navigation reopening and transition-source checks passed")
	}
}
