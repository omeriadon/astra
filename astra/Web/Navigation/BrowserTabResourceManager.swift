#if os(macOS)
import Dispatch
import Foundation

/// One process-wide coordinator for resource priority across every browser window.
/// This stores only tab identities, never strong references to controllers or views.
@MainActor
final class BrowserTabResourceManager {
	static let shared = BrowserTabResourceManager()

	enum ResourceState: String {
		case active
		case warm
		case background
		case hibernated
	}

	private var lastActivated: [UUID: Date] = [:]
	private var pressureSource: (any DispatchSourceMemoryPressure)?
	private let warmInterval: TimeInterval = 120

	private init() {
		let source = DispatchSource.makeMemoryPressureSource(
			eventMask: [.normal, .warning, .critical],
			queue: .main
		)
		source.setEventHandler { [weak self] in
			Task { @MainActor [weak self] in
				self?.memoryPressureDidChange()
			}
		}
		pressureSource = source
		source.activate()
	}

	/// This hot path touches only the old and new tabs. It never walks all
	/// browsing history, constructs WebKit state, or scans 1,000 tab controllers.
	func didSelectTab(_ id: UUID, previously previousID: UUID?) {
		lastActivated[id] = .now
		updateAuxiliaryWork(for: previousID)
		updateAuxiliaryWork(for: id)
	}

	/// Full reconciliation only runs when window membership changes, when
	/// restoration finishes, and when memory pressure arrives.
	func reconcileWindows() {
		let browsers = BrowserWindowRegistry.shared.openBrowsers.filter(\.isHydrationFinished)
		let activeIDs = Set(browsers.map(\.selectedTabID))
		var seen = Set<UUID>()
		for browser in browsers {
			for tab in browser.tabs where seen.insert(tab.id).inserted {
				if activeIDs.contains(tab.id), lastActivated[tab.id] == nil {
					lastActivated[tab.id] = .now
				}
				let isSelected = activeIDs.contains(tab.id)
				tab.controller?.previewSnapshotRefreshSuspended = !isSelected
				tab.controller?.setTopEdgeProbeActive(isSelected)
			}
		}
		lastActivated = lastActivated.filter { seen.contains($0.key) }
	}

	func state(for tab: BrowserTab) -> ResourceState {
		if tab.isHibernated { return .hibernated }
		if BrowserWindowRegistry.shared.openBrowsers.contains(where: {
			$0.isHydrationFinished && $0.selectedTabID == tab.id && $0.tab(withID: tab.id) === tab
		}) {
			return .active
		}
		if let last = lastActivated[tab.id], Date.now.timeIntervalSince(last) < warmInterval {
			return .warm
		}
		return .background
	}

	private func updateAuxiliaryWork(for id: UUID?) {
		guard let id else { return }
		let browsers = BrowserWindowRegistry.shared.openBrowsers
		let isActive = browsers.contains { $0.isHydrationFinished && $0.selectedTabID == id }
		guard let tab = browsers.lazy.compactMap({ $0.tab(withID: id) }).first else { return }
		tab.controller?.previewSnapshotRefreshSuspended = !isActive
		tab.controller?.setTopEdgeProbeActive(isActive)
	}

	private func memoryPressureDidChange() {
		guard let pressureSource else { return }
		let event = pressureSource.data
		guard event.contains(.warning) || event.contains(.critical) else { return }
		// Public WebKit APIs cannot prove that every upload, WebRTC session or
		// unsaved in-page state is restorable. Do not destroy a live WKWebView
		// solely because it is backgrounded. Reclaim Astra-owned cached images
		// immediately; explicit hibernation retains the existing safety checks.
		let browsers = BrowserWindowRegistry.shared.openBrowsers.filter(\.isHydrationFinished)
		let activeIDs = Set(browsers.map(\.selectedTabID))
		var seen = Set<UUID>()
		var reclaimed = 0
		for browser in browsers {
			for tab in browser.tabs where seen.insert(tab.id).inserted {
				guard !activeIDs.contains(tab.id), let controller = tab.controller else { continue }
				controller.previewSnapshotRefreshSuspended = true
				if controller.discardBackgroundPreviewSnapshots() {
					reclaimed += 1
				}
			}
		}
		BrowserLog.warning(.webKit, "resources.memory-pressure", metadata: [
			"severity": event.contains(.critical) ? "critical" : "warning",
			"cached_images_reclaimed": String(reclaimed),
			"tracked_tabs": String(seen.count),
		])
	}
}
#endif
