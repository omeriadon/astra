import Defaults
import Foundation
import WebKit
#if os(macOS)
	import AppKit
#elseif os(iOS)
	import UIKit
#endif

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
		let idleTime = pressureLevel == .critical ? Duration.zero : (pressureLevel == .warning ? Self.warningIdleTime : Self.normalIdleTime)
		let eligibility = currentEligibility(in: browser)
		let eligible = browser.tabs
			.filter { isEligible($0, now: now, idleTime: idleTime, context: eligibility) }
			.sorted { $0.lastInteractionAt < $1.lastInteractionAt }

		reclaimSequentially(eligible.map(\.id), idleTime: idleTime)

		let nextDelay = eligible.isEmpty
			? nextDeadlineDelay(now: now, idleTime: idleTime, browser: browser)
			: .seconds(60)
		scheduleSweep(after: nextDelay)
	}

	private func reclaimSequentially(_ ids: [UUID], idleTime: Duration) {
		reclamationTask?.cancel()
		let pressureAtStart = pressureLevel
		reclamationTask = Task { @MainActor [weak self, weak browser] in
			guard let self, let browser else { return }
			for id in ids {
				guard !Task.isCancelled,
				      pressureLevel == pressureAtStart,
				      Defaults[.automaticHibernationEnabled],
				      let tab = browser.tab(withID: id),
				      isEligible(tab, now: .now, idleTime: idleTime)
				else { continue }
				guard let controller = tab.controller else { continue }
				let activityBefore = tab.lastInteractionAt
				let navigationBefore = controller.navigationIdentifier
				guard await controller.refreshHibernationSafety(),
				      tab.controller === controller,
				      controller.navigationIdentifier == navigationBefore,
				      tab.lastInteractionAt == activityBefore,
				      Defaults[.automaticHibernationEnabled],
				      isEligible(tab, now: .now, idleTime: idleTime),
				      !Task.isCancelled, pressureLevel == pressureAtStart
				else { continue }
				guard let interactionState = controller.webViewIfLoaded?.interactionState as? Data,
				      interactionState.count <= 4 * 1024 * 1024 else { continue }
				#if os(macOS)
					let memory = browser.isPrivate ? nil : await controller.tabProcessMemorySnapshot()
					guard !Task.isCancelled, pressureLevel == pressureAtStart,
					      Defaults[.automaticHibernationEnabled],
					      tab.controller === controller,
					      controller.navigationIdentifier == navigationBefore,
					      tab.lastInteractionAt == activityBefore,
					      isEligible(tab, now: .now, idleTime: idleTime) else { continue }
				#endif
				guard browser.finishAutomaticHibernation(tab, interactionState: interactionState) else { continue }
				#if os(macOS)
					if let memory {
						Task { await BrowserController.logReclamation(for: memory) }
					}
				#endif
			}
		}
	}

	/// Snapshot the O(all-windows + all-tabs) membership/visibility inputs once
	/// per sweep. The reclaim task still rechecks each tab from current state
	/// after its WebKit suspension safety query completes.
	private struct EligibilityContext {
		let browserIsRegistered: Bool
		let ownedTabIDs: Set<UUID>
		let visibleTabIDs: Set<UUID>
		let pinnedTabIDs: Set<UUID>
		let anyDownloadActive: Bool
	}

	private func currentEligibility(in browser: Browser) -> EligibilityContext {
		let registry = BrowserWindowRegistry.shared
		let windows = registry.openBrowsers
		let pinnedTabIDs = Set(
			browser.workspace.favouriteTabIDs
				+ browser.workspace.spaces.flatMap(\.pinnedTabIDs)
		)
		// Treat a selected tab anywhere as visible, even if the ownership map
		// is changing. Conservative protection prevents a cross-window race.
		let visibleTabIDs = Set(windows.map(\.selectedTabID))
		return EligibilityContext(
			browserIsRegistered: windows.contains(where: { $0 === browser }),
			ownedTabIDs: registry.ownedTabIDs(in: browser),
			visibleTabIDs: visibleTabIDs,
			pinnedTabIDs: pinnedTabIDs,
			anyDownloadActive: browser.session.downloads.activeProgress != nil
		)
	}

	private func nextDeadlineDelay(now: Date, idleTime: Duration, browser: Browser) -> Duration {
		let eligibility = currentEligibility(in: browser)
		let seconds = browser.tabs
			.filter { isEligible($0, now: now, idleTime: .zero, context: eligibility) }
			.map { max(1, idleTime.timeInterval - now.timeIntervalSince($0.lastInteractionAt)) }
			.min() ?? idleTime.timeInterval
		return .milliseconds(Int64(max(seconds, 60) * 1000))
	}

	private func isEligible(
		_ tab: BrowserTab, now: Date, idleTime: Duration,
		context: EligibilityContext? = nil
	) -> Bool {
		guard let browser else { return false }
		let current = context ?? currentEligibility(in: browser)
		guard !tab.isHibernated,
		      current.browserIsRegistered,
		      tab.internalPage == nil,
		      tab.canHibernate,
		      // A batch sweep already traverses this browser's own collection.
		      // After an await, validate membership again to prevent stale
		      // decisions when a tab has been closed or moved to another window.
		      context != nil || browser.tabs.contains(where: { $0 === tab }),
		      tab.controller?.canAutomaticallyHibernate == true,
		      !current.visibleTabIDs.contains(tab.id),
		      current.ownedTabIDs.contains(tab.id),
		      !current.pinnedTabIDs.contains(tab.id),
		      tab.peeks.isEmpty,
		      tab.controller?.webViewIfLoaded != nil,
		      tab.controller?.webViewIfLoaded?.window == nil,
		      !current.anyDownloadActive
		else { return false }
		return idleTime == .zero || now.timeIntervalSince(tab.lastInteractionAt) >= idleTime.timeInterval
	}
}

private extension Duration {
	var timeInterval: TimeInterval {
		TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
	}
}
