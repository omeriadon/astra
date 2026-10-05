import Foundation

/// Minimal collaborators for executing the production window registry without
/// launching Astra or touching a user's persistence, WebKit or sync account.
@MainActor
final class TestSession {
	static let shared = TestSession()
}

@MainActor
final class BrowserTab {
	let id: UUID
	var isHibernated = false

	init(id: UUID = UUID()) {
		self.id = id
	}
}

struct BrowserWindowRecord {
	let windowID: UUID
	let tabIDs: [UUID]
	let selectedTabID: UUID
	let frame: String?
}

@MainActor
final class Browser {
	let windowID = UUID()
	var isPrivate = false
	var isMini = false
	let session = TestSession.shared
	var tabs: [BrowserTab]
	var selectedTabID: UUID
	var savedWindowFrame: String?
	var isHydrationFinished = true

	var selectedTab: BrowserTab? {
		tab(withID: selectedTabID)
	}

	init(tab: BrowserTab) {
		tabs = [tab]
		selectedTabID = tab.id
	}

	func tab(withID id: UUID) -> BrowserTab? {
		tabs.first { $0.id == id }
	}

	func prepareSelectedTabDisplayOwner() {}
	func configureSelectedTab() {}
	func configureOwnedTabs() {}
	func selectTab(_ id: UUID) {
		selectedTabID = id
	}

	func receiveSharedState(from _: Browser) {}
}

@MainActor
final class BrowserExtensionManager {
	static let shared = BrowserExtensionManager()
	func sync(_: Browser) {}
	func focus(_: Browser) {}
}

@MainActor
final class BrowserSync {
	static let shared = BrowserSync()
	func attach(_: Browser) {}
}

@main
struct WindowOwnershipChecks {
	@MainActor
	static func main() {
		let registry = BrowserWindowRegistry()
		let tab = BrowserTab()
		let first = Browser(tab: tab)
		let second = Browser(tab: tab)
		registry.register(first)
		registry.register(second)
		assert(registry.sharedTab(withID: tab.id, for: second) === tab)
		registry.activate(first)
		assert(registry.ownsTab(tab.id, in: first))
		assert(!registry.ownsTab(tab.id, in: second))
		assert(registry.hasActiveDuplicate(of: second))
		registry.activate(second)
		assert(registry.ownsTab(tab.id, in: second))
		assert(!registry.ownsTab(tab.id, in: first))
		assert(registry.isOpenInAnotherWindow(tab.id, than: first))
		registry.unregister(second)
		assert(registry.ownsTab(tab.id, in: first))
		assert(registry.isReferenced(tab))
		registry.unregister(first)
		assert(!registry.isReferenced(tab))
		let privateBrowser = Browser(tab: BrowserTab(id: tab.id))
		privateBrowser.isPrivate = true
		registry.register(privateBrowser)
		assert(registry.sharedTab(withID: tab.id, for: privateBrowser) == nil)
		print("Production registry ownership, transfer, close and private-isolation checks passed")
	}
}
