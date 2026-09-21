import Foundation
import Observation

@MainActor
@Observable
final class Browser {
	private(set) var tabs: [BrowserTab]
	private(set) var selectedTabID: UUID
	private(set) var persistenceErrorDescription: String?

	@ObservationIgnored
	private let persistence: BrowserPersistence?

	@ObservationIgnored
	private var persistenceTask: Task<Void, Never>?

	var selectedTab: BrowserTab? {
		tabs.first { $0.id == selectedTabID }
	}

	init() {
		let loadedTabs: [BrowserTab]
		let loadedSelectedTabID: UUID
		let loadedPersistence: BrowserPersistence?
		let loadedErrorDescription: String?

		do {
			let store = try BrowserPersistence()
			let savedTabs = try store.loadOpenTabs()
			let snapshot = try store.loadBrowserSnapshot()
			let restoredTabs = savedTabs.map {
				BrowserTab(
					id: $0.id,
					title: $0.title.isEmpty ? "New Tab" : $0.title,
					initialURL: $0.url,
					history: $0.history,
					historyIndex: $0.historyIndex
				)
			}
			let tabs = restoredTabs.isEmpty ? [BrowserTab()] : restoredTabs
			loadedTabs = tabs
			loadedSelectedTabID = tabs.first(where: { $0.id == snapshot?.selectedTabID })?.id ?? tabs[0].id
			loadedPersistence = store
			loadedErrorDescription = nil
		} catch {
			let tab = BrowserTab()
			loadedTabs = [tab]
			loadedSelectedTabID = tab.id
			loadedPersistence = nil
			loadedErrorDescription = error.localizedDescription
		}

		tabs = loadedTabs
		selectedTabID = loadedSelectedTabID
		persistence = loadedPersistence
		persistenceErrorDescription = loadedErrorDescription
		persistenceTask = nil

		for tab in loadedTabs {
			attachPersistence(to: tab)
		}
	}

	@discardableResult
	func addTab() -> BrowserTab {
		let tab = BrowserTab()
		attachPersistence(to: tab)
		tabs.append(tab)
		selectedTabID = tab.id
		schedulePersistence()
		return tab
	}

	func selectTab(_ id: UUID) {
		guard tabs.contains(where: { $0.id == id }) else { return }
		selectedTabID = id
		schedulePersistence()
	}

	func closeTab(_ id: UUID) {
		guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
		let wasSelected = selectedTabID == id
		tabs.remove(at: index)

		if tabs.isEmpty {
			addTab()
			return
		}

		if wasSelected {
			selectedTabID = tabs[min(index, tabs.count - 1)].id
		}
		schedulePersistence()
	}

	func flushPersistence() {
		persistenceTask?.cancel()
		persistenceTask = nil
		persist()
	}

	private func attachPersistence(to tab: BrowserTab) {
		tab.didChange = { [weak self] in
			self?.schedulePersistence()
		}
	}

	private func schedulePersistence() {
		guard persistence != nil else { return }
		persistenceTask?.cancel()
		persistenceTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .milliseconds(300))
			guard !Task.isCancelled, let self else { return }
			persist()
		}
	}

	private func persist() {
		guard let persistence else { return }
		do {
			try persistence.saveOpenTabs(tabs.map(\.openTab))
			try persistence.saveBrowserSnapshot(BrowserSnapshot(selectedTabID: selectedTabID))
			persistenceErrorDescription = nil
		} catch {
			persistenceErrorDescription = error.localizedDescription
		}
	}
}
