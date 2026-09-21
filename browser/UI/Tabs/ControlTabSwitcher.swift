#if os(macOS)
	import AppKit
	import Observation
	import SwiftUI

	@MainActor
	@Observable
	final class ControlTabSwitcher {
		private(set) var candidateIDs: [UUID] = []
		private(set) var highlightedTabID: UUID?
		private(set) var isPreviewVisible = false

		@ObservationIgnored
		private let browser: Browser
		@ObservationIgnored
		private var eventMonitor: Any?
		@ObservationIgnored
		private var previewTask: Task<Void, Never>?
		@ObservationIgnored
		private var switchingOrder: TabSwitchingOrder = .visibleTabList
		@ObservationIgnored
		private var sessionForward = true

		init(browser: Browser) {
			self.browser = browser
		}

		func start(order: TabSwitchingOrder) {
			switchingOrder = order
			guard eventMonitor == nil else { return }
			eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
				let isKeyDown = event.type == .keyDown
				let isTab = event.keyCode == 48
				let isControlPressed = event.modifierFlags.contains(.control)
				let isShiftPressed = event.modifierFlags.contains(.shift)
				let isHandled = MainActor.assumeIsolated {
					self?.handle(
						isKeyDown: isKeyDown,
						isTab: isTab,
						isControlPressed: isControlPressed,
						isShiftPressed: isShiftPressed
					) ?? false
				}
				return isHandled ? nil : event
			}
		}

		func stop() {
			if let eventMonitor {
				NSEvent.removeMonitor(eventMonitor)
				self.eventMonitor = nil
			}
			previewTask?.cancel()
			previewTask = nil
			endSession()
		}

		func tabsDidChange() {
			let validTabIDs = Set(browser.tabs.map(\.id))
			candidateIDs.removeAll { !validTabIDs.contains($0) }
			guard !candidateIDs.isEmpty else {
				endSession()
				return
			}
			if let highlightedTabID, !validTabIDs.contains(highlightedTabID) {
				self.highlightedTabID = candidateIDs[0]
			}
		}

		private func handle(
			isKeyDown: Bool,
			isTab: Bool,
			isControlPressed: Bool,
			isShiftPressed: Bool
		) -> Bool {
			if isKeyDown {
				guard isControlPressed, isTab else { return false }
				if candidateIDs.isEmpty {
					sessionForward = !isShiftPressed
					let order = browser.switchCandidates(
						forward: sessionForward,
						order: switchingOrder
					)
					guard !order.isEmpty else { return true }
					candidateIDs = order
					highlightedTabID = order[0]
					previewTask = Task { @MainActor [weak self] in
						try? await Task.sleep(for: .milliseconds(200))
						guard !Task.isCancelled, let self, !candidateIDs.isEmpty else { return }
						isPreviewVisible = true
					}
				} else {
					let currentIndex = candidateIDs.firstIndex(of: highlightedTabID ?? candidateIDs[0]) ?? 0
					let isForward = !isShiftPressed
					let step = isForward == sessionForward ? 1 : -1
					highlightedTabID = candidateIDs[(currentIndex + step + candidateIDs.count) % candidateIDs.count]
				}
				return true
			}

			if !candidateIDs.isEmpty, !isControlPressed {
				if let highlightedTabID {
					browser.commitTabSwitch(to: highlightedTabID)
				}
				endSession()
			}
			return false
		}

		private func endSession() {
			previewTask?.cancel()
			previewTask = nil
			candidateIDs = []
			highlightedTabID = nil
			isPreviewVisible = false
		}
	}

#endif
