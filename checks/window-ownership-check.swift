import Foundation

/// The runtime registry emits timing diagnostics. The standalone ownership
/// fixture intentionally omits OSLog and the app's full BrowserLog dependency.
enum BrowserLog {
	enum Category { case performance }
	static func clock() -> TimeInterval {
		ProcessInfo.processInfo.systemUptime
	}

	static func duration(
		_: Category, _: String,
		since _: TimeInterval, warnAboveMilliseconds _: Double,
		metadata _: [String: String]
	) {}
}

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
	func markInteraction() {}

	init(id: UUID = UUID()) {
		self.id = id
	}
}

struct BrowserWindowRecord {
	let windowID: UUID
	let tabIDs: [UUID]
	let selectedTabID: UUID
	let selectionModifiedAt: Date
	let frame: String?

	init(windowID: UUID, tabIDs: [UUID], selectedTabID: UUID,
	     selectionModifiedAt: Date, frame: String? = nil)
	{
		self.windowID = windowID
		self.tabIDs = tabIDs
		self.selectedTabID = selectedTabID
		self.selectionModifiedAt = selectionModifiedAt
		self.frame = frame
	}
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
	var selectedTabModifiedAt: Date = .distantPast
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

	var publicationCount = 0
	var receivedFromWindowIDs: [UUID] = []
	func receiveSharedState(from source: Browser) {
		receivedFromWindowIDs.append(source.windowID)
	}

	func publishSharedState(to recipients: [Browser]) {
		publicationCount += 1
		for recipient in recipients {
			recipient.receiveSharedState(from: self)
		}
	}
}

@MainActor
final class BrowserExtensionManager {
	static let shared = BrowserExtensionManager()
	func sync(_: Browser) {}
	func selectionDidChange(_: Browser) {}
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
		registry.publish(from: first)
		assert(first.publicationCount == 1, "One source publication per fan-out")
		assert(second.receivedFromWindowIDs == [first.windowID])
		assert(first.receivedFromWindowIDs.isEmpty, "Do not send to source window")
		let privateRecipient = Browser(tab: BrowserTab())
		privateRecipient.isPrivate = true
		registry.register(privateRecipient)
		registry.publish(from: first)
		assert(first.publicationCount == 2)
		assert(privateRecipient.receivedFromWindowIDs.isEmpty,
		       "Private windows must not receive normal shared state")
		registry.unregister(privateRecipient)
		registry.activate(first)
		assert(registry.ownsTab(tab.id, in: first))
		assert(!registry.ownsTab(tab.id, in: second))
		assert(registry.hasActiveDuplicate(of: second))
		registry.activate(second)
		assert(registry.ownsTab(tab.id, in: second))
		assert(!registry.ownsTab(tab.id, in: first))
		assert(registry.ownedTabIDs(in: second) == [tab.id])
		assert(registry.ownedTabIDs(in: first).isEmpty)
		// The batch lookup must have the same ownership semantics as
		// the single-tab API even for shared and unique tabs at scale.
		for index in 0 ..< 200 {
			let shared = BrowserTab()
			first.tabs.append(shared)
			if index.isMultiple(of: 2) {
				second.tabs.append(shared)
			}
		}
		for browser in [first, second] {
			let expected = Set(browser.tabs.filter {
				registry.ownsTab($0.id, in: browser)
			}.map(\.id))
			assert(registry.ownedTabIDs(in: browser) == expected)
		}
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
