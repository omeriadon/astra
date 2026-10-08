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
	private var reclamationTask: Task<Void, Never>?
	private var pressureLevel: PressureLevel = .normal

	init(browser: Browser) {
		self.browser = browser
		scheduleSweep(after: .seconds(60))
	}

	deinit {
		sweepTask?.cancel()
		reclamationTask?.cancel()
	}

	func handleMemoryPressure(_ level: PressureLevel) {
		pressureLevel = level
		scheduleSweep(after: level == .critical ? .zero : .seconds(1))
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
			.filter { isEligible($0, now: now, idleTime: pressureLevel == .critical ? .zero : idleTime) }
			.sorted { $0.lastInteractionAt < $1.lastInteractionAt }

		reclaimSequentially(eligible.map(\.id), idleTime: pressureLevel == .critical ? .zero : idleTime)

		let nextDelay = eligible.isEmpty
			? nextDeadlineDelay(now: now, idleTime: idleTime, browser: browser)
			: .seconds(60)
		scheduleSweep(after: nextDelay)
	}

	private func reclaimSequentially(_ ids: [UUID], idleTime: Duration) {
		reclamationTask?.cancel()
		reclamationTask = Task { @MainActor [weak self, weak browser] in
			guard let self, let browser else { return }
			for id in ids {
				guard !Task.isCancelled,
				      Defaults[.automaticHibernationEnabled],
				      let tab = browser.tab(withID: id),
				      isEligible(tab, now: .now, idleTime: idleTime)
				else { continue }
				let activityBefore = tab.lastInteractionAt
				await tab.controller?.refreshActivity()
				guard tab.lastInteractionAt == activityBefore,
				      Defaults[.automaticHibernationEnabled],
				      isEligible(tab, now: .now, idleTime: idleTime),
				      pressureLevel == .critical || pressureLevel == .warning || idleTime == Self.normalIdleTime
				else { continue }
				_ = browser.finishAutomaticHibernation(tab)
			}
		}
	}

	private func nextDeadlineDelay(now: Date, idleTime: Duration, browser: Browser) -> Duration {
		let seconds = browser.tabs
			.filter { isEligible($0, now: now, idleTime: .zero) }
			.map { max(1, idleTime.timeInterval - now.timeIntervalSince($0.lastInteractionAt)) }
			.min() ?? idleTime.timeInterval
		return .milliseconds(Int64(max(seconds, 60) * 1000))
	}

	private func isEligible(_ tab: BrowserTab, now: Date, idleTime: Duration) -> Bool {
		guard !tab.isHibernated,
		      tab.internalPage == nil,
			  tab.canHibernate,
		      !isVisible(tab),
		      !isPinned(tab),
		      tab.peeks.isEmpty,
		      !hasLivePeek,
		      tab.controller?.webViewIfLoaded != nil,
		      tab.controller?.webViewIfLoaded?.window == nil,
		      browser?.session.downloads.activeProgress == nil
		else { return false }
		return idleTime == .zero || now.timeIntervalSince(tab.lastInteractionAt) >= idleTime.timeInterval
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

	private var hasLivePeek: Bool {
		BrowserWindowRegistry.shared.openBrowsers.contains { browser in
			browser.tabs.contains { !$0.peeks.isEmpty }
		}
	}
}

private extension Duration {
	var timeInterval: TimeInterval {
		TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
	}
}
