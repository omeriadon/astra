import Defaults
import Foundation

@MainActor
final class BrowserHibernationManager {
	enum PressureLevel: UInt {
		case normal = 0
		case warning = 1
		case critical = 2

		init(rawValue: UInt) {
			if rawValue & 4 != 0 {
				self = .critical
			} else if rawValue & 2 != 0 {
				self = .warning
			} else {
				self = .normal
			}
		}
	}

	private static let normalIdleTime: Duration = .seconds(30 * 60)
	private static let warningIdleTime: Duration = .seconds(5 * 60)

	private weak var browser: Browser?
	private var sweepTask: Task<Void, Never>?
	private var pressureLevel: PressureLevel = .normal

	init(browser: Browser) {
		self.browser = browser
		scheduleSweep(after: .seconds(60))
	}

	func handleMemoryPressure(_ level: PressureLevel) {
		pressureLevel = level
		if level == .critical {
			sweep()
		} else {
			scheduleSweep(after: .seconds(1))
		}
	}

	private func scheduleSweep(after delay: Duration) {
		sweepTask?.cancel()
		sweepTask = Task { @MainActor [weak self] in
			do {
				try await Task.sleep(for: delay)
			} catch {
				return
			}
			guard let self, !Task.isCancelled else { return }
			sweep()
		}
	}

	private func sweep() {
		guard let browser, browser.isHydrationFinished,
		      Defaults[.automaticHibernationEnabled]
		else {
			scheduleSweep(after: .seconds(5 * 60))
			return
		}

		let now = Date.now
		let idleTime = pressureLevel == .warning ? Self.warningIdleTime : Self.normalIdleTime
		let eligible = browser.tabs
			.filter { tab in
				guard !tab.isHibernated,
				      tab.internalPage == nil,
				      tab.canHibernate,
				      !isVisible(tab),
				      !isPinned(tab)
				else { return false }
				return pressureLevel == .critical || now.timeIntervalSince(tab.lastInteractionAt) >= idleTime.timeInterval
			}
			.sorted { $0.lastInteractionAt < $1.lastInteractionAt }

		if pressureLevel == .critical {
			for tab in eligible {
				browser.hibernateTab(tab.id, onlyIfBackground: true)
			}
		} else {
			for tab in eligible {
				browser.hibernateTab(tab.id, onlyIfBackground: true)
			}
		}

		let nextDelay = eligible.isEmpty
			? nextDeadlineDelay(now: now, idleTime: idleTime, browser: browser)
			: .seconds(60)
		scheduleSweep(after: nextDelay)
	}

	private func nextDeadlineDelay(now: Date, idleTime: Duration, browser: Browser) -> Duration {
		let seconds = browser.tabs
			.filter { !$0.isHibernated && !isVisible($0) && !isPinned($0) }
			.map { max(1, idleTime.timeInterval - now.timeIntervalSince($0.lastInteractionAt)) }
			.min() ?? idleTime.timeInterval
		return .milliseconds(Int64(seconds * 1000))
	}

	private func isVisible(_ tab: BrowserTab) -> Bool {
		BrowserWindowRegistry.shared.openBrowsers.contains { browser in
			browser.selectedTabID == tab.id && BrowserWindowRegistry.shared.ownsTab(tab.id, in: browser)
		}
	}

	private func isPinned(_ tab: BrowserTab) -> Bool {
		browser?.favouriteTabs.contains { $0.id == tab.id } == true
			|| browser?.workspace.spaces.contains { $0.pinnedTabIDs.contains(tab.id) } == true
	}
}

private extension Duration {
	var timeInterval: TimeInterval {
		TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
	}
}
